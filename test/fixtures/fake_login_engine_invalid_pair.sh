#!/bin/sh
# PHASE B (Part 3) test fixture — a FAKE `--login` engine for the
# FirefoxLoginClient guard tests. Reads the one config line off stdin
# (the token carrier), then reports a loginCompleted event whose pair
# VIOLATES the guard (whitespace-only access token, empty refresh token)
# and exits 0. The client must resolve failed(invalidTokenResponse),
# never completed — a clean process exit must not mask a broken pair.
# read the ONE config line (the client keeps stdin OPEN — closing
# it is the cancel gesture — so never wait for EOF)
IFS= read -r _cfg
echo '{"event":"loginStarted","loginMode":"webchannel"}'
echo '{"event":"loginCompleted","accessToken":"   ","refreshToken":"","expiresIn":3600,"obtainedAt":"2026-11-09T00:00:00Z"}'
