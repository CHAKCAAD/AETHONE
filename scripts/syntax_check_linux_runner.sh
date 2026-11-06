#!/usr/bin/env bash
# syntax_check_linux_runner.sh — local, full-TU syntax gate for the Linux
# GTK runner's engine channel (added v4.38b, after run 42282415458 caught
# engine_channel_linux.cc:331 — a TU this sandbox's Flutter-less/GTK-less
# environment had never compiled). The Fl* surface comes from the
# signature-faithful stub at scripts/stub_include/flutter_linux/
# flutter_linux.h; the glib/gio dev headers are the real system ones.
# Catches name resolution, overloads, namespace hiding, type mismatches —
# everything except stub-fidelity itself (the stub mirrors the pinned
# 3.47.9 flutter_linux.h signature-for-signature).
#
# Usage: scripts/syntax_check_linux_runner.sh   (from the repo root or
# anywhere — paths resolve through this script's location).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pkg-config >/dev/null || { echo "pkg-config missing" >&2; exit 1; }
pkg-config --exists glib-2.0 gio-2.0 || {
  echo "glib-2.0/gio-2.0 dev headers missing (apt: libglib2.0-dev)" >&2
  exit 1
}
g++ -fsyntax-only -std=c++17 -Wall -Wextra -Werror \
  -I "$REPO_ROOT/scripts/stub_include" \
  -I "$REPO_ROOT" \
  -I "$REPO_ROOT/linux/runner" \
  $(pkg-config --cflags glib-2.0 gio-2.0) \
  "$REPO_ROOT/linux/runner/engine_channel_linux.cc"
echo "SYNTAX GREEN: engine_channel_linux.cc (stub Fl* surface, real glib)"
