#!/usr/bin/env bash
# syntax_check_linux_runner.sh — local, full-TU syntax gates for the Linux
# runner sources this sandbox cannot really build (no Flutter SDK, no GTK
# dev package). Added v4.38b for engine_channel_linux.cc (after run
# 42282415458 caught a TU this environment had never compiled); extended
# v4.39 for the new tray controller + the shared engine layer.
#
# The Fl* surface comes from the signature-faithful stub at
# scripts/stub_include/flutter_linux/flutter_linux.h; the GTK3/pixbuf
# surface for tray_controller_linux.cc from scripts/stub_include/gtk/
# gtk.h (glib/gobject/gio are the REAL system dev headers everywhere).
# desktop_shared/desktop_engine.cpp needs no stub at all (pure C++17 +
# the vendored zeptun.h) and is checked whole, both for the v4.39 UTF-8
# path round and every future edit.
#
# Catches name resolution, overloads, namespace hiding, type mismatches —
# everything except stub fidelity itself (each stub mirrors its pinned
# upstream signature-for-signature).
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

g++ -fsyntax-only -std=c++17 -Wall -Wextra -Werror \
  -I "$REPO_ROOT/scripts/stub_include" \
  -I "$REPO_ROOT" \
  -I "$REPO_ROOT/linux/runner" \
  $(pkg-config --cflags glib-2.0 gio-2.0) \
  "$REPO_ROOT/linux/runner/tray_controller_linux.cc"
echo "SYNTAX GREEN: tray_controller_linux.cc (stub GTK/pixbuf surface, real glib/gobject)"

g++ -fsyntax-only -std=c++17 -Wall -Wextra -Werror \
  -I "$REPO_ROOT" \
  -I "$REPO_ROOT/native/zeptun/include" \
  "$REPO_ROOT/desktop_shared/desktop_engine.cpp"
echo "SYNTAX GREEN: desktop_shared/desktop_engine.cpp (no stubs — real headers, Linux half)"

g++ -fsyntax-only -std=c++17 -Wall -Wextra -Werror \
  -I "$REPO_ROOT/scripts/stub_include" \
  -I "$REPO_ROOT/windows/runner" \
  "$REPO_ROOT/windows/runner/tray_icon_windows.cpp"
echo "SYNTAX GREEN: windows/runner/tray_icon_windows.cpp (stub Win32/shellapi surface — MSVC-side pre-flight)"
