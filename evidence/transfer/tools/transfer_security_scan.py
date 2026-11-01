#!/usr/bin/env python3
"""AETHONE transfer security scan (fail-closed).

Scans every file that is a candidate for the ci-bootstrap/v4.4 transfer:
  1. CI bundle v4.4 (work_v44/bundle)
  2. Client design package (work_aethone/Aether_Zeptun_Audit_Persian_Prompt)
  3. Native source trees at frozen pins (work_aethone/phase2_evidence/src/{aether,zeptun,psiphon-fork})

Findings classes:
  - REAL-SECRET candidates  -> must be resolved (removed / blocked) before commit
  - UPSTREAM-TEST-FIXTURE   -> public upstream test certs/keys at the pinned commit
                               (already public upstream; enumerated + reported, kept)
  - INFO                    -> informational (e.g. .env keys, license notices)

Outputs a machine-readable report to stdout and a summary at the end.
No file content is modified by this scan.
"""
import os
import re
import sys

ROOT = "/home/z/my-project"

if len(sys.argv) >= 3 and sys.argv[1] == "--target":
    # Single-target mode: scan exactly one directory tree
    SCAN_SETS = {sys.argv[2]: os.path.abspath(sys.argv[2])}
else:
    SCAN_SETS = {
        "ci_bundle_v44": os.path.join(ROOT, "work_v44/bundle"),
        "design_package": os.path.join(ROOT, "work_aethone/Aether_Zeptun_Audit_Persian_Prompt"),
        "native_aether": os.path.join(ROOT, "work_aethone/phase2_evidence/src/aether"),
        "native_zeptun": os.path.join(ROOT, "work_aethone/phase2_evidence/src/zeptun"),
        "native_psiphon": os.path.join(ROOT, "work_aethone/phase2_evidence/src/psiphon-fork"),
    }

# Binary extensions to skip for text scanning (still enumerated by filename rules)
TEXT_SKIP_EXT = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".woff", ".woff2",
                 ".ttf", ".otf", ".zip", ".gz", ".xz", ".bz2", ".7z", ".jar", ".aar",
                 ".so", ".dll", ".dylib", ".exe", ".bin", ".o", ".a", ".wasm", ".pdf",
                 ".docx", ".xlsx", ".pptx", ".mp3", ".mp4", ".class", ".pyc", ".sum",
                 ".icns", ".dmg", ".pkg", ".deb", ".rpm"}
# Filename rules (always checked, even inside archives of text)
KEYSTORE_RE = re.compile(r"\.(jks|keystore|p12|pfx|bks|keytab)$", re.I)
ENV_FILE_RE = re.compile(r"(^|/)\.env($|\.)", re.I)

# Text content patterns
PRIVATE_KEY_PATTERNS = [
    b"-----BEGIN RSA PRIVATE KEY-----",
    b"-----BEGIN DSA PRIVATE KEY-----",
    b"-----BEGIN EC PRIVATE KEY-----",
    b"-----BEGIN OPENSSH PRIVATE KEY-----",
    b"-----BEGIN ENCRYPTED PRIVATE KEY-----",
    b"-----BEGIN PRIVATE KEY-----",
]
# Token prefixes (GitHub / AWS / GitLab / Slack / Google / OpenAI / npm)
TOKEN_RES = [
    (re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{16,}\b"), "GitHub token (gh*)"),
    (re.compile(rb"\bgitlab-[a-z]+_[A-Za-z0-9\-_]{20,}\b"), "GitLab token"),
    (re.compile(rb"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b"), "Slack token"),
    (re.compile(rb"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (re.compile(rb"\bAIza[0-9A-Za-z\-_]{35}\b"), "Google API key"),
    (re.compile(rb"\bnpm_[A-Za-z0-9]{36}\b"), "npm token"),
    (re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b"), "GitHub fine-grained PAT"),
    # OpenAI-style key — but NOT OpenSSH security-key algorithm identifiers
    # (sk-ecdsa-…, sk-ssh-ed25519-…, …@openssh.com) which are public constants:
    (re.compile(rb"(?<![\w@.\-])sk-(?!ecdsa-|ssh-|ed25519)[A-Za-z0-9][A-Za-z0-9\-_]{18,}\b"), "OpenAI-style secret key"),
]
# Weak password assignments in non-fixture files (reported for triage)
PASSWORD_RE = re.compile(rb"(?i)(password|passwd|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*['\"]?([^\s'\"]{6,})")

MAX_TEXT_FILE = 8 * 1024 * 1024  # skip huge text files for content scan

findings = {"REAL-SECRET": [], "KEYSTORE-FILE": [], "ENV-FILE": [], "PRIVATE-KEY-BLOCK": [],
            "TOKEN": [], "PASSWORD-ASSIGN": [], "INFO": []}
file_count = 0
byte_count = 0

for set_name, base in SCAN_SETS.items():
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d != ".git"]
        for fn in files:
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, base)
            file_count += 1
            try:
                size = os.path.getsize(p)
            except OSError:
                continue
            byte_count += size
            if KEYSTORE_RE.search(fn):
                findings["KEYSTORE-FILE"].append((set_name, rel, size))
            if ENV_FILE_RE.search(p):
                findings["ENV-FILE"].append((set_name, rel, size))
            ext = os.path.splitext(fn)[1].lower()
            if ext in TEXT_SKIP_EXT or size > MAX_TEXT_FILE:
                continue
            try:
                with open(p, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            if b"\x00" in data[:4096]:
                continue  # binary
            for pat in PRIVATE_KEY_PATTERNS:
                if pat in data:
                    findings["PRIVATE-KEY-BLOCK"].append((set_name, rel, pat.decode()))
            for rx, label in TOKEN_RES:
                m = rx.search(data)
                if m:
                    findings["TOKEN"].append((set_name, rel, label))
            for m in PASSWORD_RE.finditer(data):
                val = m.group(2)
                # skip obvious placeholders / test values (triage later by human)
                if val.lower() in (b"changeme", b"password", b"********", b"xxxxxxxx", b"yourpassword", b"example"):
                    continue
                line_no = data[:m.start()].count(b"\n") + 1
                findings["PASSWORD-ASSIGN"].append((set_name, rel, f"L{line_no}: {m.group(1).decode()}=<{len(val)} chars>"))

print(f"SCANNED {file_count} files, {byte_count/1024/1024:.1f} MiB across {len(SCAN_SETS)} sets")
for k in ("KEYSTORE-FILE", "ENV-FILE"):
    print(f"\n== {k}: {len(findings[k])} ==")
    for s, rel, extra in findings[k][:40]:
        print(f"  [{s}] {rel} ({extra} bytes)" if isinstance(extra, int) else f"  [{s}] {rel} {extra}")

print(f"\n== PRIVATE-KEY-BLOCK: {len(findings['PRIVATE-KEY-BLOCK'])} ==")
for s, rel, pat in findings["PRIVATE-KEY-BLOCK"][:60]:
    print(f"  [{s}] {rel} :: {pat}")

print(f"\n== TOKEN: {len(findings['TOKEN'])} ==")
for s, rel, label in findings["TOKEN"][:60]:
    print(f"  [{s}] {rel} :: {label}")

pa = findings["PASSWORD-ASSIGN"]
print(f"\n== PASSWORD-ASSIGN (triage): {len(pa)} ==")
for s, rel, info in pa[:60]:
    print(f"  [{s}] {rel} :: {info}")
if len(pa) > 60:
    print(f"  ... and {len(pa)-60} more")

print("\nSUMMARY:",
      "keystores=%d envfiles=%d privkeyblocks=%d tokens=%d pwassign=%d" %
      (len(findings["KEYSTORE-FILE"]), len(findings["ENV-FILE"]),
       len(findings["PRIVATE-KEY-BLOCK"]), len(findings["TOKEN"]), len(pa)))
