// Stage 2 per-app routing — functional PoC fixtures.
//
// These tests drive the REAL engine (external device, userspace stack, socks5
// handler) with a flow-owner judge that routes by the ORIGINAL source port —
// the host-side stand-in for "which app opened this flow". Two exits are
// distinguishable per route: a recording SOCKS5 server per socks5 route and a
// plain echo server for the direct route. What is proven here, end to end:
//   * per-flow handler selection (a flow dials the route's upstream, not the
//     global one),
//   * direct-route flows exiting WITHOUT any proxy,
//   * fail-closed behavior for unavailable routes,
//   * live route-table updates (established flows keep their route, new flows
//     re-resolve),
//   * per-flow UDP routing through socks5 vs direct,
//   * DNS of direct-routed apps forwarded to the real resolver while
//     default-routed apps keep fake-IP answers.
const std = @import("std");
const addr = @import("../addr.zig");
const config = @import("../config.zig");
const engine = @import("../engine.zig");
const verdict = @import("../flow/verdict.zig");
const socks5 = @import("../handler/socks5.zig");
const sys = @import("../io/sys.zig");
const parse = @import("../packet/parse.zig");
const stats = @import("../stats.zig");
const external = @import("../device/external.zig");
const h = @import("helpers.zig");

const linux = std.os.linux;

fn routeTestDebug() bool {
    // PoC instrumentation: flip to true (temporarily, locally) to install the
    // stderr log sink and run these fixtures at debug level while debugging.
    return false;
}

// ---------------------------------------------------------------------------
// The flow-owner judge: routes by ORIGINAL source port (the test's "app id").
// Ports 40001..40008 map to routes 1..8; everything else is the default.
// ---------------------------------------------------------------------------

fn routeForPort(port: u16) u16 {
    if (port >= 40001 and port <= 40008) return port - 40000;
    if (port >= 42001 and port <= 42008) return port - 42000;
    return 0;
}

fn portJudge(_: ?*anyopaque, flow: *const verdict.Flow) callconv(.c) u32 {
    return @as(u32, routeForPort(flow.source_port)) << 2; // action .proxy
}

// ---------------------------------------------------------------------------
// A recording SOCKS5 server: no-auth CONNECT relayed to the requested target
// (the tests point targets at a plain echo), UDP ASSOCIATE with framed echo.
// The counters are the exit proof — which server a flow actually used.
// ---------------------------------------------------------------------------

const Socks5Recorder = struct {
    fd: i32 = -1,
    port: u16 = 0,
    stop: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    connects: std.atomic.Value(u32) = .init(0),
    udp_associates: std.atomic.Value(u32) = .init(0),
    bytes: std.atomic.Value(u64) = .init(0),
    udp_bytes: std.atomic.Value(u64) = .init(0),

    fn start(self: *Socks5Recorder) !void {
        self.fd = try h.blockingSocket(.v4, false);
        _ = sys.setsockoptInt(self.fd, linux.SOL.SOCKET, linux.SO.REUSEADDR, 1);
        var sa = sys.Sockaddr.fromEndpoint(try addr.Endpoint.parse("127.0.0.1:0"));
        if (sys.bind(self.fd, &sa) < 0) return error.BindFailed;
        if (sys.listen(self.fd, 64) < 0) return error.ListenFailed;
        _ = sys.getsockname(self.fd, &sa);
        self.port = sa.toEndpoint().?.port;
        h.setRecvTimeout(self.fd, 25);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    fn deinit(self: *Socks5Recorder) void {
        self.stop.store(true, .release);
        if (self.thread) |t| t.join();
        sys.close(self.fd);
    }

    fn run(self: *Socks5Recorder) void {
        while (!self.stop.load(.acquire)) {
            const r = sys.linuxResult(linux.accept4(self.fd, null, null, linux.SOCK.CLOEXEC));
            if (r < 0) continue;
            const t = std.Thread.spawn(.{}, session, .{ self, r }) catch {
                sys.close(r);
                continue;
            };
            t.detach();
        }
    }

    fn session(self: *Socks5Recorder, fd: i32) void {
        defer sys.close(fd);
        h.setRecvTimeout(fd, 5000);
        var hdr: [2]u8 = undefined;
        if (!readFull(fd, &hdr) or hdr[0] != 5 or hdr[1] == 0) return;
        var methods: [255]u8 = undefined;
        if (!readFull(fd, methods[0..hdr[1]])) return;
        if (std.mem.indexOfScalar(u8, methods[0..hdr[1]], 0) == null) {
            _ = writeFull(fd, &[_]u8{ 5, 0xff });
            return;
        }
        if (!writeFull(fd, &[_]u8{ 5, 0 })) return;
        var req: [4]u8 = undefined;
        if (!readFull(fd, &req) or req[0] != 5) return;
        var target: addr.Endpoint = .{};
        switch (req[3]) {
            1 => {
                var b: [6]u8 = undefined;
                if (!readFull(fd, &b)) return;
                target = .{ .addr = addr.Address.v4(b[0..4].*), .port = std.mem.readInt(u16, b[4..6], .big) };
            },
            3 => {
                var l: [1]u8 = undefined;
                if (!readFull(fd, &l)) return;
                var b: [257]u8 = undefined;
                if (!readFull(fd, b[0 .. @as(usize, l[0]) + 2])) return;
                const host = b[0..l[0]];
                target = .{
                    .addr = addr.Address.parse(host) catch return,
                    .port = std.mem.readInt(u16, b[l[0]..][0..2], .big),
                };
            },
            else => return,
        }
        switch (req[1]) {
            1 => { // CONNECT
                const up = h.blockingSocket(target.addr.family, false) catch {
                    _ = writeFull(fd, &[_]u8{ 5, 5, 0, 1, 0, 0, 0, 0, 0, 0 });
                    return;
                };
                defer sys.close(up);
                h.setRecvTimeout(up, 5000);
                const usa = sys.Sockaddr.fromEndpoint(target);
                if (sys.connect(up, &usa) < 0) {
                    _ = writeFull(fd, &[_]u8{ 5, 5, 0, 1, 0, 0, 0, 0, 0, 0 });
                    return;
                }
                if (!writeFull(fd, &[_]u8{ 5, 0, 0, 1, 0, 0, 0, 0, 0, 0 })) return;
                _ = self.connects.fetchAdd(1, .monotonic);
                self.relay(fd, up);
            },
            3 => { // UDP ASSOCIATE — echo datagrams back to the client
                _ = self.udp_associates.fetchAdd(1, .monotonic);
                self.udpAssociate(fd);
            },
            else => {},
        }
    }

    fn relay(self: *Socks5Recorder, a: i32, b: i32) void {
        const Pair = struct {
            src: i32,
            dst: i32,
            owner: *Socks5Recorder,
            fn run(p: @This()) void {
                var buf: [65536]u8 = undefined;
                while (true) {
                    const n = sys.linuxResult(linux.read(p.src, &buf, buf.len));
                    if (n <= 0) break;
                    _ = p.owner.bytes.fetchAdd(@intCast(n), .monotonic);
                    if (!writeFull(p.dst, buf[0..@intCast(n)])) break;
                }
                _ = linux.shutdown(p.dst, linux.SHUT.WR);
            }
        };
        const t = std.Thread.spawn(.{}, Pair.run, .{Pair{ .src = b, .dst = a, .owner = self }}) catch return;
        Pair.run(.{ .src = a, .dst = b, .owner = self });
        t.join();
    }

    fn udpAssociate(self: *Socks5Recorder, ctrl: i32) void {
        const ufd = h.blockingSocket(.v4, true) catch {
            _ = writeFull(ctrl, &[_]u8{ 5, 1, 0, 1, 0, 0, 0, 0, 0, 0 });
            return;
        };
        defer sys.close(ufd);
        var sa = sys.Sockaddr.fromEndpoint(addr.Endpoint.parse("127.0.0.1:0") catch unreachable);
        if (sys.bind(ufd, &sa) < 0) return;
        _ = sys.getsockname(ufd, &sa);
        const bound = sa.toEndpoint().?;
        var reply: [22]u8 = .{ 5, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        reply[3] = 1;
        @memcpy(reply[4..8], bound.addr.bytes[0..4]);
        std.mem.writeInt(u16, reply[8..10], bound.port, .big);
        if (!writeFull(ctrl, reply[0..10])) return;
        h.setRecvTimeout(ufd, 25);
        var client: ?sys.Sockaddr = null;
        var buf: [65536]u8 = undefined;
        while (!self.stop.load(.acquire)) {
            var from: sys.Sockaddr = .{};
            const n = sys.recvfrom(ufd, &buf, 0, &from);
            if (n <= 0) continue;
            const from_ep = from.toEndpoint() orelse continue;
            const is_client = if (client) |*c| (c.toEndpoint() orelse addr.Endpoint{}).eql(from_ep) else true;
            if (is_client) {
                client = from;
                // RFC 1928 UDP ASSOCIATE datagram: RSV RSV FRAG ATYP ADDR PORT
                // payload — parseUdpHeader/encodeUdpHeader, not the fwd_udp
                // stream framing.
                const f = socks5.parseUdpHeader(buf[0..@intCast(n)]) catch continue;
                const payload = buf[f.header_len..@intCast(n)];
                _ = self.udp_bytes.fetchAdd(payload.len, .monotonic);
                // Echo the payload straight back with the original dst as src.
                var out: [socks5.max_udp_header + 65536]u8 = undefined;
                const src_ep = f.src orelse addr.Endpoint{ .addr = addr.Address.v4(@splat(127)), .port = f.port };
                const hl = socks5.encodeUdpHeader(&out, src_ep);
                @memcpy(out[hl..][0..payload.len], payload);
                _ = sys.sendto(ufd, out[0 .. hl + payload.len], 0, &from);
            }
        }
    }
};

fn readFull(fd: i32, buf: []u8) bool {
    var off: usize = 0;
    while (off < buf.len) {
        const n = sys.linuxResult(linux.read(fd, buf[off..].ptr, buf.len - off));
        if (n <= 0) return false;
        off += @intCast(n);
    }
    return true;
}

fn writeFull(fd: i32, buf: []const u8) bool {
    var off: usize = 0;
    while (off < buf.len) {
        const n = sys.linuxResult(linux.sendto(fd, buf[off..].ptr, buf.len - off, linux.MSG.NOSIGNAL, null, 0));
        if (n <= 0) return false;
        off += @intCast(n);
    }
    return true;
}

// ---------------------------------------------------------------------------
// Engine + packet-client scaffolding (external device, mirroring engine_tests).
// ---------------------------------------------------------------------------

fn routedConfig(default_server: addr.Endpoint, entries: []const config.RouteEntry) config.Config {
    var cfg = config.Config.fromPreset(.mobile);
    cfg.device.kind = .external;
    cfg.stack.mode = .userspace;
    cfg.handler.kind = .socks5;
    cfg.handler.socks5.server = default_server;
    cfg.handler.socks5.pool_size = 0;
    cfg.io.workers = 1;
    cfg.log_level = .warn;
    cfg.routes = .{ .entries = entries };
    return cfg;
}

const TcpClient = struct {
    e: *engine.Engine,
    collector: *h.Collector,
    client: addr.Endpoint,
    server: addr.Endpoint,
    snd_nxt: u32 = 1000,
    rcv_nxt: u32 = 0,
    peer_wscale: u8 = 0,
    peer_window: u32 = 0,
    received: std.ArrayList(u8) = .empty,
    got_fin: bool = false,
    acked: u32 = 0,

    fn send(self: *TcpClient, seg: h.TcpSeg) !void {
        var buf: [2048]u8 = undefined;
        const pkt = h.buildTcp4(&buf, self.client, self.server, seg);
        const pk: external.Packet = .{ .data = pkt.ptr, .len = pkt.len };
        if (self.e.external.?.injectBatch(&.{pk}) != 1) return error.InjectFailed;
    }

    fn pump(self: *TcpClient, timeout_ms: u64) !?parse.Tcp {
        var out: [2048]u8 = undefined;
        const raw = self.collector.next(timeout_ms, &out) orelse return null;
        const p = try parse.parse(raw);
        if (p.l4 != .tcp) return error.UnexpectedProtocol;
        if (!parse.l4ChecksumValid(raw, p)) return error.BadChecksum;
        const t = p.l4.tcp;
        if (t.flags.rst) return error.Reset;
        if (t.flags.ack) {
            self.acked = t.ack;
            self.peer_window = @as(u32, t.window) << @intCast(self.peer_wscale);
        }
        if (p.payload_len > 0) {
            if (t.seq == self.rcv_nxt) {
                try self.received.appendSlice(std.testing.allocator, raw[p.payload_off..][0..p.payload_len]);
                self.rcv_nxt +%= p.payload_len;
            }
            try self.send(.{ .seq = self.snd_nxt, .ack = self.rcv_nxt, .flags = 0x10 });
        }
        if (t.flags.fin and t.seq +% p.payload_len == self.rcv_nxt) {
            self.rcv_nxt +%= 1;
            self.got_fin = true;
            try self.send(.{ .seq = self.snd_nxt, .ack = self.rcv_nxt, .flags = 0x10 });
        }
        return t;
    }

    /// Open a flow, push `payload`, wait for the full echo, return whether a
    /// RST was observed instead (fail-closed signal).
    fn roundTrip(self: *TcpClient, payload: []const u8, deadline_ms: u64) !bool {
        const syn_opts = [_]u8{ 2, 4, 0x05, 0xb4, 4, 2, 1, 3, 3, 7 };
        try self.send(.{ .seq = 999, .ack = 0, .flags = 0x02, .options = &syn_opts });
        var out: [2048]u8 = undefined;
        const synack_raw = self.collector.next(3000, &out) orelse return error.NoSynAck;
        const sp = try parse.parse(synack_raw);
        const sa = sp.l4.tcp;
        if (sa.flags.rst) return true; // fail-closed: refused before handshake
        try std.testing.expect(sa.flags.syn and sa.flags.ack);
        const so = parse.parseTcpOptions(synack_raw[sp.l4_off + 20 .. sp.payload_off]);
        self.peer_wscale = so.wscale;
        self.rcv_nxt = sa.seq +% 1;
        try self.send(.{ .seq = self.snd_nxt, .ack = self.rcv_nxt, .flags = 0x10 });
        var sent: usize = 0;
        const deadline = sys.monotonicMs() + deadline_ms;
        while (self.received.items.len < payload.len and sys.monotonicMs() < deadline) {
            const inflight = self.snd_nxt -% self.acked;
            if (sent < payload.len and (self.acked == 0 or inflight < 8000)) {
                const n = @min(1200, payload.len - sent);
                try self.send(.{ .seq = self.snd_nxt, .ack = self.rcv_nxt, .flags = 0x18, .payload = payload[sent..][0..n] });
                self.snd_nxt +%= @intCast(n);
                sent += n;
            }
            _ = self.pump(if (sent < payload.len) 5 else 100) catch |err| switch (err) {
                error.Reset => return true,
                else => return err,
            };
        }
        return false;
    }

    fn deinit(self: *TcpClient) void {
        self.received.deinit(std.testing.allocator);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "per-flow routing: three apps, three exits (socks5 default, socks5 route, direct route)" {
    if (!sys.is_linux) return error.SkipZigTest;
    var recorder_a: Socks5Recorder = .{}; // default route exit
    try recorder_a.start();
    defer recorder_a.deinit();
    var recorder_b: Socks5Recorder = .{}; // route 1 exit
    try recorder_b.start();
    defer recorder_b.deinit();
    var echo: h.TcpEcho = .{ .fd = -1, .port = 0 }; // route 2 exit (direct)
    try echo.start();
    defer echo.deinit();

    const entries = [_]config.RouteEntry{
        .{ .id = .init("route-b"), .kind = .socks5, .server = .{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_b.port } },
        .{ .id = .init("direct"), .kind = .direct },
    };
    var cfg = routedConfig(.{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_a.port }, &entries);
    cfg.handler.socks5.pool_size = 4; // mobile default: the warm pool must stay default-only
    const e = try engine.Engine.create(std.testing.allocator, cfg);
    defer e.destroy();
    var collector: h.Collector = .{};
    e.external.?.setOutput(h.Collector.output, &collector);
    e.setJudge(portJudge, null);
    try e.start();

    const target = addr.Endpoint{ .addr = try addr.Address.parse("127.0.0.1"), .port = echo.port };
    const payload = "per-app routing payload 0001";

    // App "1" (port 40001 -> route 1): must exit via recorder_b.
    var app1: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40001"), .server = target };
    defer app1.deinit();
    try std.testing.expect(!try app1.roundTrip(payload, 8000));
    try std.testing.expectEqualStrings(payload, app1.received.items);

    // App "2" (port 40002 -> route 2): must exit DIRECT via the echo server.
    var app2: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40002"), .server = target };
    defer app2.deinit();
    try std.testing.expect(!try app2.roundTrip(payload, 8000));
    try std.testing.expectEqualStrings(payload, app2.received.items);
    // The echo received app1's payload (relayed by recorder_b) AND app2's
    // payload (dialed directly) — the two distinguishable exits both reach
    // the target, which is exactly what the exit-IP test on a device checks.
    try std.testing.expectEqual(2 * payload.len, echo.bytes.load(.acquire));

    // App "3" (port 40003 -> default): must exit via recorder_a.
    var app3: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40003"), .server = target };
    defer app3.deinit();
    try std.testing.expect(!try app3.roundTrip(payload, 8000));
    try std.testing.expectEqualStrings(payload, app3.received.items);

    // Exit proofs:
    //  * route-1 flows dialed recorder_b EXACTLY once each — a route dial
    //    never consumes a pooled (default-server) connection;
    //  * every flow's payload reached the shared echo target (two via
    //    proxies, one directly);
    //  * the default flow reached recorder_a (directly or pooled).
    try std.testing.expectEqual(@as(u32, 1), recorder_b.connects.load(.acquire));
    try std.testing.expectEqual(@as(u64, 2 * payload.len), recorder_b.bytes.load(.acquire));
    try std.testing.expect(recorder_a.connects.load(.acquire) >= 1);
    try std.testing.expectEqual(3 * payload.len, echo.bytes.load(.acquire));

    var snap: stats.Snapshot = .{};
    e.snapshot(&snap);
    try std.testing.expectEqual(@as(u64, 3), snap.route_asked);
    try std.testing.expectEqual(@as(u64, 2), snap.route_assigned);
    // Port 40003 asked for route 3, which this 2-entry table does not have:
    // a stale/out-of-range number degrades to the DEFAULT route, counted —
    // never to another app's route (app3 reached recorder_a, above).
    try std.testing.expectEqual(@as(u64, 1), snap.route_fallback);
    try std.testing.expectEqual(@as(u64, 0), snap.route_direct_fake);
    e.stop();
}

test "unavailable route fails closed; other apps unaffected" {
    if (!sys.is_linux) return error.SkipZigTest;
    var recorder_a: Socks5Recorder = .{};
    try recorder_a.start();
    defer recorder_a.deinit();
    var echo: h.TcpEcho = .{ .fd = -1, .port = 0 };
    try echo.start();
    defer echo.deinit();

    // A "dead" socks5 route: bind a socket to grab a free port, then close it
    // so connects are refused.
    var dead: Socks5Recorder = .{};
    try dead.start();
    const dead_port = dead.port;
    dead.deinit();

    const entries = [_]config.RouteEntry{
        .{ .id = .init("dead"), .kind = .socks5, .server = .{ .addr = try addr.Address.parse("127.0.0.1"), .port = dead_port } },
    };
    const e = try engine.Engine.create(std.testing.allocator, routedConfig(
        .{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_a.port },
        &entries,
    ));
    defer e.destroy();
    var collector: h.Collector = .{};
    e.external.?.setOutput(h.Collector.output, &collector);
    e.setJudge(portJudge, null);
    try e.start();

    const target = addr.Endpoint{ .addr = try addr.Address.parse("127.0.0.1"), .port = echo.port };
    const payload = "fail closed, not sideways";

    // The flow assigned to the dead route must FAIL (RST observed) — it must
    // never fall back to the default recorder.
    var app1: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40001"), .server = target };
    defer app1.deinit();
    const reset = app1.roundTrip(payload, 15_000) catch |err| switch (err) {
        error.NoSynAck => true, // engine aborted before even the SYN-ACK
        else => return err,
    };
    try std.testing.expect(reset);
    try std.testing.expectEqual(@as(u32, 0), recorder_a.connects.load(.acquire));

    // Drain any stragglers from the aborted flow (late ACKs / duplicate
    // RSTs the engine emitted while tearing the dead-route conn down) so
    // they cannot be misread as the next flow's packets.
    {
        var stale: [2048]u8 = undefined;
        while (collector.next(30, &stale) != null) {}
    }

    // A default-route app on the same engine still works.
    var app3: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40003"), .server = target };
    defer app3.deinit();
    try std.testing.expect(!try app3.roundTrip(payload, 8000));
    try std.testing.expectEqualStrings(payload, app3.received.items);
    try std.testing.expectEqual(@as(u32, 1), recorder_a.connects.load(.acquire));
    e.stop();
}

test "live route update: established flow keeps its route, new flows re-resolve" {
    if (!sys.is_linux) return error.SkipZigTest;
    var recorder_a: Socks5Recorder = .{};
    try recorder_a.start();
    defer recorder_a.deinit();
    var recorder_b: Socks5Recorder = .{};
    try recorder_b.start();
    defer recorder_b.deinit();
    var echo: h.TcpEcho = .{ .fd = -1, .port = 0 };
    try echo.start();
    defer echo.deinit();

    const entries = [_]config.RouteEntry{
        .{ .id = .init("route-b"), .kind = .socks5, .server = .{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_b.port } },
    };
    const e = try engine.Engine.create(std.testing.allocator, routedConfig(
        .{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_a.port },
        &entries,
    ));
    defer e.destroy();
    var collector: h.Collector = .{};
    e.external.?.setOutput(h.Collector.output, &collector);
    e.setJudge(portJudge, null);
    try e.start();
    try std.testing.expectEqual(@as(usize, 1), e.routeCount());

    const target = addr.Endpoint{ .addr = try addr.Address.parse("127.0.0.1"), .port = echo.port };
    const first = "before the swap";
    const second = "after the swap";

    // Establish a route-1 flow through recorder_b.
    var app1: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40001"), .server = target };
    defer app1.deinit();
    try std.testing.expect(!try app1.roundTrip(first, 8000));
    try std.testing.expectEqualStrings(first, app1.received.items);
    const bytes_before = recorder_b.bytes.load(.acquire);
    try std.testing.expectEqual(@as(u32, 1), recorder_b.connects.load(.acquire));

    // Live swap: route 1 becomes the direct handler. fake_ip is off, so no
    // dns.upstream is required for a direct entry.
    const updated = [_]config.RouteEntry{
        .{ .id = .init("direct"), .kind = .direct },
    };
    try e.updateRoutes(&updated);
    try std.testing.expectEqual(@as(usize, 1), e.routeCount());

    // The ESTABLISHED flow keeps streaming through recorder_b.
    var more: [4000]u8 = undefined;
    for (&more, 0..) |*b, i| b.* = @truncate(i *% 37);
    var sent2: usize = 0;
    const deadline = sys.monotonicMs() + 8000;
    while (app1.received.items.len < first.len + more.len and sys.monotonicMs() < deadline) {
        const inflight = app1.snd_nxt -% app1.acked;
        if (sent2 < more.len and (app1.acked == 0 or inflight < 8000)) {
            const n = @min(1200, more.len - sent2);
            try app1.send(.{ .seq = app1.snd_nxt, .ack = app1.rcv_nxt, .flags = 0x18, .payload = more[sent2..][0..n] });
            app1.snd_nxt +%= @intCast(n);
            sent2 += n;
        }
        _ = try app1.pump(5);
    }
    try std.testing.expectEqual(first.len + more.len, app1.received.items.len);
    const bytes_after = recorder_b.bytes.load(.acquire);
    // The relay counts both directions (client->target and target->client).
    try std.testing.expectEqual(bytes_before + 2 * more.len, bytes_after);

    // A NEW route-1 flow exits through the updated (direct) route.
    var app1b: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40005"), .server = target };
    defer app1b.deinit();
    try std.testing.expect(!try app1b.roundTrip(second, 8000));
    try std.testing.expectEqualStrings(second, app1b.received.items);
    // recorder_b saw no new connect; the echo (shared target of all flows)
    // saw the established flow's bytes plus the new flow's direct payload.
    try std.testing.expectEqual(@as(u32, 1), recorder_b.connects.load(.acquire));
    try std.testing.expectEqual(first.len + more.len + second.len, echo.bytes.load(.acquire));

    // An invalid update is rejected and leaves the active table untouched.
    const bad = [_]config.RouteEntry{
        .{ .id = .init(""), .kind = .socks5, .server = .{ .addr = try addr.Address.parse("127.0.0.1"), .port = 1 } },
    };
    try std.testing.expectError(error.InvalidArgument, e.updateRoutes(&bad));
    try std.testing.expectEqual(@as(usize, 1), e.routeCount());
    e.stop();
}

test "per-flow UDP routing: direct route vs socks5 default" {
    if (!sys.is_linux) return error.SkipZigTest;
    if (routeTestDebug()) {
        @import("../log.zig").setSink(h.debugSink, null);
    }
    var recorder_a: Socks5Recorder = .{};
    try recorder_a.start();
    defer recorder_a.deinit();
    var udp_echo: h.UdpEcho = .{ .fd = -1, .port = 0 };
    try udp_echo.start();
    defer udp_echo.deinit();

    const entries = [_]config.RouteEntry{
        .{ .id = .init("direct"), .kind = .direct },
    };
    var cfg = routedConfig(.{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_a.port }, &entries);
    if (routeTestDebug()) cfg.log_level = .debug;
    const e = try engine.Engine.create(std.testing.allocator, cfg);
    defer e.destroy();
    var collector: h.Collector = .{};
    e.external.?.setOutput(h.Collector.output, &collector);
    e.setJudge(portJudge, null);
    try e.start();

    const server = addr.Endpoint{ .addr = try addr.Address.parse("127.0.0.1"), .port = udp_echo.port };
    const payload = "udp per-app routing";
    var pkt_buf: [256]u8 = undefined;

    // Direct-routed UDP flow (port 40001 -> route 1 = direct).
    const pkt = h.buildUdp4(&pkt_buf, try addr.Endpoint.parse("10.0.0.2:40001"), server, payload);
    const pk: external.Packet = .{ .data = pkt.ptr, .len = pkt.len };
    try std.testing.expectEqual(@as(usize, 1), e.external.?.injectBatch(&.{pk}));
    var out: [2048]u8 = undefined;
    const reply = collector.next(4000, &out) orelse return error.NoDirectUdpReply;
    const p = try parse.parse(reply);
    try std.testing.expect(p.l4 == .udp);
    try std.testing.expectEqualStrings(payload, reply[p.payload_off..][0..p.payload_len]);
    try std.testing.expectEqual(@as(u32, 0), recorder_a.udp_associates.load(.acquire));

    // Default-routed UDP flow (port 40003): goes through the socks5
    // UDP ASSOCIATE path of recorder_a and comes back framed.
    const pkt2 = h.buildUdp4(&pkt_buf, try addr.Endpoint.parse("10.0.0.2:40003"), server, payload);
    const pk2: external.Packet = .{ .data = pkt2.ptr, .len = pkt2.len };
    try std.testing.expectEqual(@as(usize, 1), e.external.?.injectBatch(&.{pk2}));
    const reply2 = collector.next(4000, &out) orelse return error.NoSocksUdpReply;
    const p2 = try parse.parse(reply2);
    try std.testing.expect(p2.l4 == .udp);
    try std.testing.expectEqualStrings(payload, reply2[p2.payload_off..][0..p2.payload_len]);
    try std.testing.expectEqual(@as(u32, 1), recorder_a.udp_associates.load(.acquire));
    try std.testing.expectEqual(@as(u64, payload.len), recorder_a.udp_bytes.load(.acquire));

    var snap: stats.Snapshot = .{};
    e.snapshot(&snap);
    try std.testing.expectEqual(@as(u64, 2), snap.route_asked);
    try std.testing.expectEqual(@as(u64, 1), snap.route_assigned);
    e.stop();
}

test "direct-routed DNS is forwarded to the real resolver; default DNS stays fake" {
    if (!sys.is_linux) return error.SkipZigTest;
    var recorder_a: Socks5Recorder = .{};
    try recorder_a.start();
    defer recorder_a.deinit();
    // The "real resolver": a UDP echo. The forwarded query must arrive here
    // verbatim and its echo must reach the app.
    var resolver: h.UdpEcho = .{ .fd = -1, .port = 0 };
    try resolver.start();
    defer resolver.deinit();

    const entries = [_]config.RouteEntry{
        .{ .id = .init("direct"), .kind = .direct },
    };
    var cfg = routedConfig(.{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_a.port }, &entries);
    cfg.dns.fake_ip = true;
    cfg.dns.upstream = .{ .addr = try addr.Address.parse("127.0.0.1"), .port = resolver.port };
    const e = try engine.Engine.create(std.testing.allocator, cfg);
    defer e.destroy();
    var collector: h.Collector = .{};
    e.external.?.setOutput(h.Collector.output, &collector);
    e.setJudge(portJudge, null);
    try e.start();

    // A minimal A query for "example.com." (qtype 1, qclass 1).
    const query = [_]u8{
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        7, 'e', 'x', 'a', 'm', 'p', 'l', 'e',
        3, 'c', 'o', 'm',
        0, 0x00, 0x01, 0x00, 0x01,
    };
    const dns_server = try addr.Endpoint.parse("172.19.0.2:53");
    var pkt_buf: [512]u8 = undefined;

    // Direct-routed app (port 42001 -> route 1): its query must be FORWARDED
    // to the configured upstream — never answered from the fake table.
    const pkt = h.buildUdp4(&pkt_buf, try addr.Endpoint.parse("10.0.0.2:42001"), dns_server, &query);
    const pk: external.Packet = .{ .data = pkt.ptr, .len = pkt.len };
    try std.testing.expectEqual(@as(usize, 1), e.external.?.injectBatch(&.{pk}));
    var out: [2048]u8 = undefined;
    const reply = collector.next(4000, &out) orelse return error.NoForwardedDnsReply;
    const p = try parse.parse(reply);
    try std.testing.expect(p.l4 == .udp);
    try std.testing.expectEqual(@as(u16, 53), p.l4.udp.src_port);
    try std.testing.expectEqualStrings(&query, reply[p.payload_off..][0..p.payload_len]);

    // Default-routed app (port 41003 is not in the judge map -> route 0):
    // fake-IP answer, no upstream traffic.
    const pkt2 = h.buildUdp4(&pkt_buf, try addr.Endpoint.parse("10.0.0.2:41003"), dns_server, &query);
    const pk2: external.Packet = .{ .data = pkt2.ptr, .len = pkt2.len };
    try std.testing.expectEqual(@as(usize, 1), e.external.?.injectBatch(&.{pk2}));
    const reply2 = collector.next(4000, &out) orelse return error.NoFakeDnsReply;
    const p2 = try parse.parse(reply2);
    try std.testing.expect(p2.l4 == .udp);
    // A fake answer: header + question + one A record whose RDATA (the last
    // four payload bytes) lies in 198.18.0.0/15.
    try std.testing.expect(p2.payload_len >= 12 + 17 + 12 + 4);
    const rdata = reply2[reply2.len - 4 ..];
    try std.testing.expectEqual(@as(u8, 198), rdata[0]);
    try std.testing.expect(rdata[1] == 18 or rdata[1] == 19);

    var snap: stats.Snapshot = .{};
    e.snapshot(&snap);
    try std.testing.expectEqual(@as(u64, 1), snap.dns_fake_answers); // only the default app's query
    try std.testing.expectEqual(@as(u64, 1), snap.route_assigned); // only the direct app's query
    e.stop();
}

test "direct-routed flow to a fake-IP destination fails closed" {
    if (!sys.is_linux) return error.SkipZigTest;
    var recorder_a: Socks5Recorder = .{};
    try recorder_a.start();
    defer recorder_a.deinit();
    var resolver: h.UdpEcho = .{ .fd = -1, .port = 0 };
    try resolver.start();
    defer resolver.deinit();

    const entries = [_]config.RouteEntry{
        .{ .id = .init("direct"), .kind = .direct },
    };
    var cfg = routedConfig(.{ .addr = try addr.Address.parse("127.0.0.1"), .port = recorder_a.port }, &entries);
    cfg.dns.fake_ip = true;
    cfg.dns.upstream = .{ .addr = try addr.Address.parse("127.0.0.1"), .port = resolver.port };
    const e = try engine.Engine.create(std.testing.allocator, cfg);
    defer e.destroy();
    var collector: h.Collector = .{};
    e.external.?.setOutput(h.Collector.output, &collector);
    e.setJudge(portJudge, null);
    try e.start();

    // A TCP SYN straight to a fake-IP address from a direct-routed "app"
    // (this is the shape of a flow whose DNS attribution failed): the route
    // cannot execute it, so it must be refused — never tunneled via default.
    const fake_target = try addr.Endpoint.parse("198.18.0.7:443");
    var cl: TcpClient = .{ .e = e, .collector = &collector, .client = try addr.Endpoint.parse("10.0.0.2:40001"), .server = fake_target };
    defer cl.deinit();
    const reset = cl.roundTrip("leak check", 3000) catch |err| switch (err) {
        error.NoSynAck => true,
        else => return err,
    };
    try std.testing.expect(reset);
    try std.testing.expectEqual(@as(u32, 0), recorder_a.connects.load(.acquire));

    var snap: stats.Snapshot = .{};
    e.snapshot(&snap);
    try std.testing.expectEqual(@as(u64, 1), snap.route_direct_fake);
    try std.testing.expectEqual(@as(u64, 0), snap.tcp_opened);
    e.stop();
}
