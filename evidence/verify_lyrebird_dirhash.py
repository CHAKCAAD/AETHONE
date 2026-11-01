#!/usr/bin/env python3
"""AETHONE v4.1 evidence — verify proxy.golang.org zip content against the
sum.golang.org recorded h1: dirhash for lyrebird@v0.0.0-20260312101154-fc105a03c0e0.

Implements golang.org/x/mod/sumdb/dirhash Hash1 + HashZip exactly as published
(fetched from proxy.golang.org golang.org/x/mod@v0.42.0, saved as
dirhash evidence): for each file (sorted by name) write
"<hex sha256 of content>  <name>\n" (two spaces), then
h1 = "h1:" + base64std(sha256(concatenated lines)).

This verifies the CONTENT layer only: it proves the zip served by the proxy
matches the content hash recorded in the checksum database for that
pseudo-version. It does NOT verify the SumDB record signature (done by the Go
toolchain at build time) and does NOT authenticate the git commit identity.
"""
import base64
import hashlib
import sys
import zipfile

# zip path: first CLI arg, else ./lyrebird_proxy.zip next to this script
ZIP = sys.argv[1] if len(sys.argv) > 1 else \
    __import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "lyrebird_proxy.zip")
SUMDB_H1 = "uzPZpf45zlpdB/Gyk8P+QGjsuEeReitMpsaPiBmHncM="  # module h1 from sum.golang.org lookup
SUMDB_GOMOD_H1 = "uCIr865SJMJ4LHn90G3+L/MmMCA8cix7ZAvV74HcWLo="  # go.mod h1 from sum.golang.org lookup


def hash1(files_and_contents):
    """files_and_contents: list of (name, bytes). Returns the h1: string."""
    h = hashlib.sha256()
    for name, content in sorted(files_and_contents, key=lambda x: x[0]):
        if "\n" in name:
            raise ValueError("filenames with newlines are not supported")
        hf = hashlib.sha256(content).hexdigest()
        h.update(f"{hf}  {name}\n".encode())
    return "h1:" + base64.standard_b64encode(h.digest()).decode()


def main():
    entries = []
    with zipfile.ZipFile(ZIP) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            entries.append((info.filename, z.read(info)))
    print(f"zip: {ZIP}")
    print(f"files hashed: {len(entries)}")
    module_h1 = hash1(entries)
    print(f"computed module h1:  {module_h1}")
    print(f"sum.golang.org h1:   h1:{SUMDB_H1}")
    if module_h1 == "h1:" + SUMDB_H1:
        print("RESULT: MATCH — proxy zip content == checksum-DB-recorded content for "
              "lyrebird@v0.0.0-20260312101154-fc105a03c0e0")
    else:
        print("RESULT: MISMATCH — do not claim content verification")
        sys.exit(1)

    # go.mod hash attempt: dirhash over the single file named "go.mod"
    prefix = "gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird@v0.0.0-20260312101154-fc105a03c0e0/"
    gomod = [c for n, c in entries if n == prefix + "go.mod"]
    if gomod:
        gomod_h1 = hash1([("go.mod", gomod[0])])
        print(f"computed go.mod h1:  {gomod_h1}")
        print(f"sum.golang.org:      h1:{SUMDB_GOMOD_H1}")
        print("go.mod hash:", "MATCH" if gomod_h1 == "h1:" + SUMDB_GOMOD_H1 else
              "NO MATCH (not claimed; only the module-level hash above is the verified content layer)")

    # also record the sha256 of the go.mod content for the evidence file
    gomod_sha = hashlib.sha256(gomod[0]).hexdigest() if gomod else "n/a"
    print(f"go.mod content sha256: {gomod_sha}")


if __name__ == "__main__":
    main()
