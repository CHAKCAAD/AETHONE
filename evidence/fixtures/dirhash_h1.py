#!/usr/bin/env python3
# AETHONE — independent re-implementation of the Go module H1 dirhash
# (golang.org/x/mod/sumdb/dirhash, Hash1 + HashZip), used to verify the
# lyrebird proxy zip against the public checksum database record.
#
# Algorithm — verified against x/mod v0.29.0 source (sumdb/dirhash/hash.go)
# AND against the live sum.golang.org record for the pinned lyrebird version:
#   HashZip: files = ALL zip entry names (full names, no prefix stripping),
#            sorted; content = zip entry content (empty for dir entries)
#   Hash1:   h = sha256; for each file (sorted):
#              h <- hex(sha256(content)) + "  " + <name> + "\n"
#            (NO "N files, M bytes" header line — that was the pre-2023
#            algorithm; the current one is the one implemented here)
#   result = "h1:" + base64std(sha256 digest)
#
# Usage: dirhash_h1.py <zip>            -> prints the H1 dirhash
#        dirhash_h1.py <zip> --gomod    -> additionally prints the sumdb
#                                          /go.mod line hash for comparison
import base64, hashlib, sys, zipfile

def h1_zip(zip_path):
    z = zipfile.ZipFile(zip_path)
    names = sorted(i.filename for i in z.infolist())
    h = hashlib.sha256()
    for n in names:
        data = b'' if n.endswith('/') else z.read(n)
        h.update(hashlib.sha256(data).hexdigest().encode() + b"  " + n.encode() + b"\n")
    return "h1:" + base64.b64encode(h.digest()).decode(), names

def h1_gomod(zip_path, names):
    z = zipfile.ZipFile(zip_path)
    mod_names = [n for n in names if n.endswith('/go.mod')]
    assert len(mod_names) == 1, f"expected exactly one go.mod, got {mod_names}"
    data = z.read(mod_names[0])
    # the sumdb "<module> <version>/go.mod h1:..." line is Hash1 over the
    # SINGLE file named "go.mod" (no prefix): one line, hex(sha256) + "  go.mod"
    h = hashlib.sha256()
    h.update(hashlib.sha256(data).hexdigest().encode() + b"  go.mod\n")
    return "h1:" + base64.b64encode(h.digest()).decode()

def main():
    zip_path = sys.argv[1]
    digest, names = h1_zip(zip_path)
    print(f"files_in_zip: {len(names)}")
    print(f"local_H1_dirhash: {digest}")
    if '--gomod' in sys.argv:
        print(f"local_gomod_H1: {h1_gomod(zip_path, names)}")

if __name__ == '__main__':
    main()
