#!/bin/sh
# PHASE B (Part 3) test fixture — a FAKE `--login` engine that reports a
# WELL-FORMED loginCompleted pair (both tokens non-empty, non-blank,
# string-typed). The client must resolve completed and hand the exact
# pair to the caller (the adapter vaults it). NOTE: the token SHAPES here
# are synthetic test values only — the guard deliberately does NOT
# validate any real token format (the Phase B rule: no invented formats).
# read the ONE config line (the client keeps stdin OPEN — closing
# it is the cancel gesture — so never wait for EOF)
IFS= read -r _cfg
echo '{"event":"loginStarted","loginMode":"webchannel"}'
echo '{"event":"loginCompleted","accessToken":"at_test_0123456789abcdef0123456789abcdef","refreshToken":"rt_test_0123456789abcdef0123456789abcdef","expiresIn":3600,"obtainedAt":"2026-11-09T00:00:00Z"}'
