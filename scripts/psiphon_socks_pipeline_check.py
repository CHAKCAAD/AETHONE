#!/usr/bin/env python3
"""The psiphon tunnel-mode data-path root cause, proven at the byte level.

Owner defect (round 13 addendum): psiphon PROXY mode works, psiphon TUNNEL
mode shows Connected but exchanges no data — in every app version.

Root cause (source-verified at the frozen pins):
  * zeptun @ 08a1ab05, src/handler/socks5.zig encodeHandshake(pipeline=true)
    sends greeting + request in ONE write; the desktop preset defaults
    pipeline=.auto (=true, no username) and optimistic_data=true (request +
    the client's early payload in one writev). Pooled connections are ALWAYS
    pipelined (handler.zig: d.pipelined = true on the takeWarm path).
  * psiphon-tunnel-core @ 83aa73b9, psiphon/common/goptlib/socks.go
    socksFlushReadBuffer(): after the auth negotiation AND after the command
    read, ANY buffered leftover byte is an ERROR ("N bytes left after SOCKS
    message") and the connection is closed. Aether's psiphon chain/only
    listeners (1821 relay / 1819 direct) are served by exactly this server.
  * aether's own socks.rs (1819/1820 for the plain and tor families) reads
    the stream sequentially with no flush check — pipelining is harmless
    there, which is why ONLY the psiphon family breaks.

This script replays both handshake styles against a faithful port of
goptlib's accept path (bufio buffered reads + the three flush checks) using
the byte sequences zeptun's own test vectors define:
  greeting+request pipelined : 05 01 00 | 05 01 00 03 0b "example.com" 01 bb
  sequential                 : 05 01 00 → (reply 05 00) → request alone
  optimistic data            : request + b"GET / HTTP/1.0\r\n\r\n" in one write
"""

import sys


class GoptlibServer:
    """Faithful port of the goptlib SOCKS5 accept path (socks.go):
    socks5NegotiateAuth → socks5Authenticate → socks5ReadCommand, each with
    the socksFlushReadBuffer leftover check; bufio semantics = the kernel
    hands the reader whole TCP segments, which the reader buffers."""

    def __init__(self):
        self.buf = b""      # the bufio.Reader buffer
        self.written = b""  # everything the server sent back
        self.closed = False
        self.error = None

    def _feed(self, segment):
        self.buf += segment

    def _read(self, n):
        if len(self.buf) < n:
            self._fail("client vanished mid-message (NeedMore → conn.Close)")
            return b""
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _read_until(self, end):
        i = self.buf.find(end)
        if i < 0:
            self._fail("client vanished mid-message")
            return b""
        out, self.buf = self.buf[: i + 1], self.buf[i + 1 :]
        return out

    def _flush_check(self, where):
        # socksFlushReadBuffer: buffered leftover after a SOCKS message is fatal
        if self.buf:
            self._fail(
                f"{where}: {len(self.buf)} bytes left after SOCKS message"
            )

    def _fail(self, msg):
        self.error = msg
        self.closed = True  # conn.Close() on the error path

    def accept(self, segments):
        """segments: the TCP segments the client wrote, in order."""
        if not segments:
            self._fail("no greeting")
            return
        # socksPeekByte + socks5NegotiateAuth
        self._feed(segments[0])
        if self._read(1) != b"\x05":
            self._fail("not socks5")
            return
        nmethods = self._read(1)[0]
        methods = self._read(nmethods)
        if 0x00 not in methods:
            self._fail("no acceptable methods")
            return
        self.written += b"\x05\x00"  # method reply
        self._flush_check("socks5NegotiateAuth")  # ← kills pipelined requests
        if self.closed:
            return
        # no auth → socks5ReadCommand (fresh segment = a later TCP write)
        if len(segments) > 1:
            self._feed(segments[1])
        if not self.buf:
            self._fail("socks5ReadCommand: no command arrived")
            return
        if self._read(1) != b"\x05":
            self._fail("bad command version")
            return
        cmd = self._read(1)[0]
        if self._read(1) != b"\x00":
            self._fail("bad reserved")
            return
        atyp = self._read(1)[0]
        if atyp == 0x01:
            self._read(4)
        elif atyp == 0x03:
            ln = self._read(1)[0]
            self._read(ln)
        elif atyp == 0x04:
            self._read(16)
        else:
            self._fail("bad atyp")
            return
        self._read(2)
        self._flush_check("socks5ReadCommand")  # ← kills optimistic data
        if self.closed:
            return
        # Grant
        self.written += b"\x05\x00\x00\x01" + b"\x00" * 4 + b"\x00\x00"
        self.served = True


def zeptun_pipelined(domain=b"example.com", port=443):
    """zeptun encodeHandshake(pipeline=true): greeting+request, one write."""
    req = bytes([5, 1, 0, 3, len(domain)]) + domain + bytes([port >> 8, port & 0xFF])
    return [b"\x05\x01\x00" + req]


def zeptun_sequential(domain=b"example.com", port=443, optimistic=b""):
    """pipeline=false: greeting first; after the method reply the request —
    with optimistic_data=true the client payload rides the same writev."""
    req = bytes([5, 1, 0, 3, len(domain)]) + domain + bytes([port >> 8, port & 0xFF])
    segments = [b"\x05\x01\x00", req]
    if optimistic:
        segments[1] += optimistic
    return segments


def run(label, segments):
    srv = GoptlibServer()
    srv.accept(segments)
    ok = getattr(srv, "served", False)
    verdict = "SERVED (data flows)" if ok else f"REJECTED: {srv.error}"
    print(f"  {label:<52} → {verdict}")
    return ok


if __name__ == "__main__":
    print("goptlib (psiphon's SOCKS5 server) vs zeptun handshake styles")
    print("=" * 96)
    results = {}
    results["pipelined_default"] = run(
        "zeptun DEFAULT (pipeline=auto→on): greeting+request", zeptun_pipelined()
    )
    results["optimistic"] = run(
        "zeptun pipeline=off BUT optimistic_data=on", zeptun_sequential(optimistic=b"GET / HTTP/1.0\r\n\r\n")
    )
    results["fixed"] = run(
        "THE FIX: pipeline=off + optimistic_data=off", zeptun_sequential()
    )
    print("=" * 96)
    expected = {  # what the source says must happen
        "pipelined_default": False,
        "optimistic": False,
        "fixed": True,
    }
    if results != expected:
        print("MISMATCH vs the source-derived expectation:")
        for k in expected:
            print(f"  {k}: expected {expected[k]}, got {results[k]}")
        sys.exit(1)
    print(
        "PROVEN: the psiphon family's goptlib listener rejects zeptun's\n"
        "pipelined handshake AND its optimistic data; the sequential style\n"
        "(pipeline=false, optimistic_data=false) is served. That is the\n"
        "tunnel-mode data-path fix; proxy mode never hit it because the\n"
        "walk's probe speaks strictly sequential SOCKS5."
    )
