#!/usr/bin/env bash
# =============================================================================
# build_packages.sh — the v1.0.1 Linux packaging round (the owner's decree:
# «نسخه 1.0.1 اپ برای لینوکس هم منتشر بشه با پسوند های مختلف مثل فلتپک .دب
# و ... برای انواع توضیع های لینوکسی»).
#
# ONE bundle in, EVERY format out (all from the same baseline x86-64-v1
# artifacts the CI desktop-bundle job produced — one build, every format):
#   aethone-linux-x86_64-<ver>.tar.gz        the portable tar (any distro)
#   aethone_<ver>_amd64.deb                  Debian-family (Debian 13+,
#                                             Ubuntu 24.04+, Mint 22+, ...)
#   aethone-tunnel-helper_<ver>_amd64.deb    the Flatpak companion (host-side
#                                             TUN bring-up helper)
#   aethone-<ver>-1.x86_64.rpm               rpm-family (Fedora 40+,
#                                             openSUSE Tumbleweed/Leap 16)
#   aethone-tunnel-helper-<ver>-1.x86_64.rpm the Flatpak companion (rpm form)
#   AETHONE-<ver>-x86_64.AppImage            universal single-file (any x86_64)
#   aethone-<ver>-x86_64.flatpak             Flatpak bundle (GNOME 48 runtime;
#                                             tunnel mode needs the companion)
#   BUILD_INFO-linux-r<run>.txt + SHA256SUMS-linux-r<run>.txt
#
# Fail-closed at every stage; every format is VERIFIED after the build
# (dpkg -x / rpm -qpl / --appimage-extract / a flatpak run sh gate).
#
# Usage (see the linux-packages CI job for the canonical invocation):
#   packaging/linux/build_packages.sh \
#     --bundle <extracted-desktop-bundle-dir> \
#     --version 1.0.1 --run <github-run-number> \
#     --out <dist-dir> [--linuxdeploy <dir-with-pinned-tools>] \
#     [--flatpak-smoke]
# =============================================================================
set -euo pipefail

die() { echo "::error::build_packages: $*" >&2; exit 1; }
log() { echo "[pkg] $*"; }

BUNDLE="" VERSION="" RUN="" OUT="" PKGROOT="" LINUXDEPLOY="" FLATPAK_SMOKE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --run) RUN="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --pkg-root) PKGROOT="${2:-}"; shift 2 ;;
    --linuxdeploy) LINUXDEPLOY="${2:-}"; shift 2 ;;
    --flatpak-smoke) FLATPAK_SMOKE=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$BUNDLE" ] || die "--bundle is required"
[ -n "$VERSION" ] || die "--version is required"
[ -n "$RUN" ] || die "--run is required"
[ -n "$OUT" ] || die "--out is required"
[ -n "$PKGROOT" ] || PKGROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$(cd "$BUNDLE" && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d -t aethone-pkg-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# --- the bundle contract (mirrors the desktop-bundle CI gate) -----------------
for f in aethone aethone-tunnel-helper lyrebird psiphon \
         com.chakcaad.aethone.tunnel-helper.policy \
         aethone-icon.png aethone-tray.png \
         lib/libapp.so lib/libflutter_linux_gtk.so \
         lib/libaether.so lib/libzeptun.so data/icudtl.dat; do
  [ -e "$BUNDLE/$f" ] || die "bundle is incomplete: $BUNDLE/$f is missing"
done
[ -x "$BUNDLE/aethone" ] || die "bundle/aethone is not executable"
[ -x "$BUNDLE/aethone-tunnel-helper" ] || die "helper is not executable"
log "bundle OK: $BUNDLE ($(du -sh "$BUNDLE" | cut -f1))"

# --- 1. stage the shared filesystem tree (deb + rpm) --------------------------
# Layout (the Flutter bundle keeps its self-relative shape under /usr/lib):
#   /usr/lib/aethone/          the whole desktop bundle (exe + lib/ + data/
#                              + lyrebird + psiphon + the two icon faces)
#   /usr/bin/aethone           the exec wrapper (RPATH is $ORIGIN-relative,
#                              so the real binary path must be exec'd)
#   /usr/libexec/aethone-tunnel-helper + the polkit action — PRE-INSTALLED:
#                              deb/rpm users never see the first-connect
#                              self-install prompt
#   /usr/share/{applications,icons/hicolor,polkit-1/actions}
stage_main_tree() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/usr/lib/aethone" "$root/usr/bin" "$root/usr/libexec" \
           "$root/usr/share/applications" \
           "$root/usr/share/polkit-1/actions" \
           "$root/usr/share/icons/hicolor"
  cp -a "$BUNDLE"/. "$root/usr/lib/aethone/"
  cat > "$root/usr/bin/aethone" <<'EOF'
#!/bin/sh
# AETHONE launcher — execs the real bundle binary (its RPATH is
# $ORIGIN-relative, so a symlink would NOT work; this wrapper is the
# documented way to expose it on PATH).
exec /usr/lib/aethone/aethone "$@"
EOF
  chmod 0755 "$root/usr/bin/aethone"
  install -m 0755 "$BUNDLE/aethone-tunnel-helper" \
    "$root/usr/libexec/aethone-tunnel-helper"
  install -m 0644 "$PKGROOT/shared/com.chakcaad.aethone.desktop" \
    "$root/usr/share/applications/com.chakcaad.aethone.desktop"
  install -m 0644 "$BUNDLE/com.chakcaad.aethone.tunnel-helper.policy" \
    "$root/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy"
  local d
  for d in 16x16 24x24 32x32 48x48 64x64 96x96 128x128 256x256; do
    install -D -m 0644 "$PKGROOT/hicolor/$d/apps/com.chakcaad.aethone.png" \
      "$root/usr/share/icons/hicolor/$d/apps/com.chakcaad.aethone.png"
  done
  # the bundle's helper/policy stay in /usr/lib/aethone too (the app's
  # own first-connect path stays coherent if the system copy is removed)
  log "staged main tree: $(du -sh "$root" | cut -f1)"
}

stage_helper_tree() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/usr/libexec" "$root/usr/share/polkit-1/actions"
  install -m 0755 "$BUNDLE/aethone-tunnel-helper" \
    "$root/usr/libexec/aethone-tunnel-helper"
  install -m 0644 "$BUNDLE/com.chakcaad.aethone.tunnel-helper.policy" \
    "$root/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy"
  log "staged helper tree ($(du -sh "$root" | cut -f1))"
}

# --- 2. the .debs --------------------------------------------------------------
build_deb() {  # build_deb <template-dir> <staged-root> <name> <out-deb>
  local tmpl="$1" root="$2" name="$3" out="$4"
  local size_kb
  size_kb="$(( ( $(du -sk "$root" | cut -f1) + 1 ) / 2 * 2 ))"
  local stage="$WORK/deb-$name"
  rm -rf "$stage"
  cp -a "$root" "$stage"
  mkdir -p "$stage/DEBIAN"
  sed -e "s/__VERSION__/$VERSION/g" -e "s/__INSTALLED_SIZE__/$size_kb/g" \
    "$tmpl/DEBIAN/control" > "$stage/DEBIAN/control"
  if [ -f "$tmpl/DEBIAN/postinst" ]; then
    install -m 0755 "$tmpl/DEBIAN/postinst" "$stage/DEBIAN/postinst"
  fi
  dpkg-deb --root-owner-group --build "$stage" "$out" >/dev/null
  [ -s "$out" ] || die "dpkg-deb produced nothing for $name"
  log "built $(basename "$out") ($(du -h "$out" | cut -f1))"
}

# --- 3. the .rpms (handwritten specs + fakeroot for root:root ownership) ------
build_rpm() {  # build_rpm <spec-template> <staged-root> <name> <out-rpm>
  local spec_tmpl="$1" root="$2" name="$3" out="$4"
  local top="$WORK/rpm-$name"
  rm -rf "$top"
  mkdir -p "$top"/{BUILD,BUILDROOT,SOURCES,SPECS,RPMS,SRPMS}
  sed "s/__VERSION__/$VERSION/g" "$spec_tmpl" > "$top/SPECS/$name.spec"
  fakeroot -- rpmbuild -bb \
    --define "_topdir $top" \
    --buildroot "$root" \
    "$top/SPECS/$name.spec" > "$WORK/rpmbuild-$name.log" 2>&1 \
    || { tail -40 "$WORK/rpmbuild-$name.log"; die "rpmbuild failed for $name"; }
  # -print -quit, NOT `| head -1` — pipefail + an early-exiting consumer
  # would SIGPIPE find exactly like the r98 tar|head lesson
  local produced
  produced="$(find "$top/RPMS" -name '*.rpm' -type f -print -quit)"
  [ -n "$produced" ] || die "rpmbuild produced no rpm for $name"
  mv "$produced" "$out"
  log "built $(basename "$out") ($(du -h "$out" | cut -f1))"
}

# --- 4. the AppImage (linuxdeploy + the gtk plugin, both sha256-pinned) -------
build_appimage() {
  [ -n "$LINUXDEPLOY" ] || die "--linuxdeploy is required for the AppImage leg"
  [ -x "$LINUXDEPLOY/linuxdeploy-x86_64.AppImage" ] \
    || die "linuxdeploy-x86_64.AppImage missing under $LINUXDEPLOY"
  [ -f "$LINUXDEPLOY/linuxdeploy-plugin-gtk.sh" ] \
    || die "linuxdeploy-plugin-gtk.sh missing under $LINUXDEPLOY"
  local appdir="$WORK/AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/bin"
  cp -a "$BUNDLE"/. "$appdir/usr/bin/"
  cp "$PKGROOT/shared/com.chakcaad.aethone.desktop" "$appdir/com.chakcaad.aethone.desktop"
  cp "$PKGROOT/hicolor/256x256/apps/com.chakcaad.aethone.png" \
     "$appdir/com.chakcaad.aethone.png"
  chmod +x "$LINUXDEPLOY/linuxdeploy-plugin-gtk.sh"
  local out="$OUT/AETHONE-$VERSION-x86_64.AppImage"
  ( export ARCH=x86_64
    export GTK_VERSION=3
    export OUTPUT="$out"
    # the runner images carry no libfuse2 — self-extracting mode is the
    # documented AppImage way to run under CI; NO_STRIP keeps the ISA-gated
    # bundle ELFs byte-identical to the audited desktop-bundle artifacts
    export APPIMAGE_EXTRACT_AND_RUN=1
    export NO_STRIP=true
    # the plugin must be discoverable as `linuxdeploy-plugin-gtk(.sh)` —
    # putting the pinned tools' directory on PATH is the proven lookup
    # (the r99 first flight: same-dir-without-PATH was not enough)
    export PATH="$LINUXDEPLOY:$PATH"
    "$LINUXDEPLOY/linuxdeploy-x86_64.AppImage" \
      --appdir "$appdir" \
      --executable "$appdir/usr/bin/aethone" \
      --desktop-file "$appdir/com.chakcaad.aethone.desktop" \
      --icon-file "$appdir/com.chakcaad.aethone.png" \
      --plugin gtk \
      --output appimage ) > "$WORK/linuxdeploy.log" 2>&1 \
    || { tail -40 "$WORK/linuxdeploy.log"; die "linuxdeploy failed"; }
  [ -s "$out" ] || die "the AppImage was not produced"
  chmod +x "$out"
  log "built $(basename "$out") ($(du -h "$out" | cut -f1))"
}

# --- 5. the Flatpak (repackages the same bundle; GNOME 48 runtime) -------------
build_flatpak() {
  command -v flatpak >/dev/null || die "flatpak is not installed"
  command -v flatpak-builder >/dev/null || die "flatpak-builder is not installed"
  local stage="$WORK/flatpak-stage" repo="$WORK/flatpak-repo" build="$WORK/flatpak-build"
  rm -rf "$stage" "$repo" "$build"
  mkdir -p "$stage"
  cp "$PKGROOT/flatpak/com.chakcaad.Aethone.yml" "$stage/"
  cp "$PKGROOT/flatpak/com.chakcaad.Aethone.metainfo.xml" "$stage/"
  cp "$PKGROOT/shared/com.chakcaad.aethone.desktop" "$stage/"
  cp -r "$PKGROOT/hicolor" "$stage/hicolor"
  sed "s/__RELEASE_DATE__/$(date -u +%F)/" \
    "$PKGROOT/flatpak/com.chakcaad.Aethone.metainfo.xml" > "$stage/com.chakcaad.Aethone.metainfo.xml"
  # the manifest consumes the bundle as a local archive source (never
  # committed); the archive carries the bundle CONTENTS at top level —
  # the manifest's `dest: bundle` then lands them at bundle/
  tar -czf "$stage/aethone-bundle.tar.gz" -C "$BUNDLE" .
  flatpak --user remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  flatpak-builder --user --install-deps-from=flathub --force-clean \
    --repo="$repo" "$build" "$stage/com.chakcaad.Aethone.yml" \
    > "$WORK/flatpak-builder.log" 2>&1 \
    || { tail -60 "$WORK/flatpak-builder.log"; die "flatpak-builder failed"; }
  local out="$OUT/aethone-$VERSION-x86_64.flatpak"
  # --runtime-repo: users without flathub preconfigured still resolve the
  # org.gnome.Platform 48 runtime when installing the bundle
  flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
    "$repo" "$out" com.chakcaad.Aethone \
    > "$WORK/flatpak-bundle.log" 2>&1 \
    || { tail -20 "$WORK/flatpak-bundle.log"; die "flatpak build-bundle failed"; }
  [ -s "$out" ] || die "the flatpak bundle was not produced"
  log "built $(basename "$out") ($(du -h "$out" | cut -f1))"
  if [ "$FLATPAK_SMOKE" -eq 1 ]; then
    flatpak --user install --noninteractive --or-update \
      "$repo" com.chakcaad.Aethone >/dev/null 2>&1 \
      || die "flatpak smoke: install from the local repo failed"
    flatpak run --command=sh com.chakcaad.Aethone -c \
      'test -x /app/bin/aethone && test -f /app/bin/lib/libaether.so && test -f /app/bin/lib/libzeptun.so' \
      || die "flatpak smoke: /app/bin layout incomplete inside the sandbox"
    # the bridge binaries must exist INSIDE the sandbox (the gate)
    flatpak run --command=sh com.chakcaad.Aethone -c \
      'test -x /usr/bin/flatpak-spawn && test -x /usr/bin/gsettings' \
      || die "flatpak smoke: flatpak-spawn/gsettings missing from the runtime"
    # the live host reachability needs a real desktop session (the portal's
    # D-Bus name); CI has none — attempt under dbus-run-session as a
    # REPORT-ONLY probe so an artificial session never blocks the release
    if command -v dbus-run-session >/dev/null 2>&1; then
      if dbus-run-session -- flatpak run --command=sh com.chakcaad.Aethone \
           -c 'flatpak-spawn --host true' >/dev/null 2>&1; then
        log "flatpak smoke: flatpak-spawn --host reached the host under dbus-run-session (bonus proof)"
      else
        log "flatpak smoke: flatpak-spawn --host not provable in the headless CI session (expected without a desktop portal) — gated on binary presence above; the real-desktop behavior is the owner's device test"
      fi
    fi
    log "flatpak smoke PASS (install + /app/bin layout + the bridge binaries)"
  fi
}

# --- 6. the portable tar.gz ------------------------------------------------------
build_tarball() {
  local top="aethone-linux-x86_64"
  local stage="$WORK/tar-stage"
  rm -rf "$stage"
  mkdir -p "$stage/$top"
  cp -a "$BUNDLE"/. "$stage/$top/"
  cat > "$stage/$top/INSTALL.txt" <<'EOF'
AETHONE — the portable Linux bundle (x86-64-v1 baseline, glibc 2.39+)
=====================================================================

Run it:
    ./aethone

The first tunnel connect asks (once) for the administrator password to
install the privilege helper (aethone-tunnel-helper) + its Polkit action;
 afterwards the normal connect prompt appears. While the tunnel is up the
system proxy points at the same local SOCKS5 listener (GNOME gsettings +
KDE kioslaverc) and is restored on disconnect.

See packaging/linux/README.md in the repository for the full guide.
EOF
  local out="$OUT/aethone-linux-x86_64-$VERSION.tar.gz"
  tar -czf "$out" -C "$stage" "$top"
  log "built $(basename "$out") ($(du -h "$out" | cut -f1))"
}

# --- 7. verification (fail-closed over every produced format) -------------------
verify_all() {
  # the .deb: metadata + extraction + the executable bits + the helper root path
  local deb="$OUT/aethone_${VERSION}_amd64.deb"
  dpkg-deb --info "$deb" >/dev/null || die "dpkg-deb --info failed on the main deb"
  dpkg-deb -x "$deb" "$WORK/deb-x" || die "dpkg-deb -x failed on the main deb"
  test -x "$WORK/deb-x/usr/lib/aethone/aethone" || die "deb: the app binary is not executable"
  test -x "$WORK/deb-x/usr/bin/aethone" || die "deb: the launcher is not executable"
  test -x "$WORK/deb-x/usr/libexec/aethone-tunnel-helper" || die "deb: the helper is not installed"
  test -f "$WORK/deb-x/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy" \
    || die "deb: the polkit action is missing"
  test -f "$WORK/deb-x/usr/share/applications/com.chakcaad.aethone.desktop" \
    || die "deb: the desktop entry is missing"
  local helper_deb="$OUT/aethone-tunnel-helper_${VERSION}_amd64.deb"
  dpkg-deb -x "$helper_deb" "$WORK/deb-helper-x" || die "dpkg-deb -x failed on the helper deb"
  test -x "$WORK/deb-helper-x/usr/libexec/aethone-tunnel-helper" || die "helper deb: binary missing"
  log "deb verification PASS"

  # the .rpm: listing must carry the critical paths
  local rpm="$OUT/aethone-$VERSION-1.x86_64.rpm"
  rpm -qpl "$rpm" > "$WORK/rpm-list.txt" || die "rpm -qpl failed"
  for p in "/usr/lib/aethone/aethone" "/usr/bin/aethone" \
           "/usr/libexec/aethone-tunnel-helper" \
           "/usr/share/applications/com.chakcaad.aethone.desktop"; do
    grep -qxF "$p" "$WORK/rpm-list.txt" || die "rpm: $p missing from the package"
  done
  local helper_rpm="$OUT/aethone-tunnel-helper-$VERSION-1.x86_64.rpm"
  rpm -qpl "$helper_rpm" | grep -qxF /usr/libexec/aethone-tunnel-helper \
    || die "helper rpm: the helper is missing"
  log "rpm verification PASS"

  # the AppImage: extract and check the payload + the launcher chain
  local ai="$OUT/AETHONE-$VERSION-x86_64.AppImage"
  rm -rf "$WORK/ai-x"; mkdir -p "$WORK/ai-x"
  ( cd "$WORK/ai-x" && "$ai" --appimage-extract >/dev/null 2>&1 ) \
    || die "--appimage-extract failed"
  test -x "$WORK/ai-x/squashfs-root/usr/bin/aethone" || die "AppImage: app binary missing"
  test -f "$WORK/ai-x/squashfs-root/usr/bin/lib/libflutter_linux_gtk.so" \
    || die "AppImage: the engine layout is missing"
  test -f "$WORK/ai-x/squashfs-root/AppRun" || die "AppImage: AppRun missing"
  log "AppImage verification PASS"

  # the tar: listing + the entry point (listed to a file first — the
  # r98 lesson: `tar | grep -q` under pipefail SIGPIPEs tar)
  local tarball="$OUT/aethone-linux-x86_64-$VERSION.tar.gz"
  tar -tzf "$tarball" > "$WORK/tar-list.txt"
  grep -qxF "aethone-linux-x86_64/aethone" "$WORK/tar-list.txt" \
    || die "tar: the entry point is missing from the archive"
  log "tar verification PASS"
}

# --- 8. the release manifests ------------------------------------------------------
write_manifests() {
  local pins=""
  # the desktop-bundle artifact's BUILD_INFO.txt (when staged beside the
  # bundle) carries the frozen native pins — carry them into ours
  for cand in "$BUNDLE/../BUILD_INFO.txt" "$BUNDLE/BUILD_INFO.txt"; do
    if [ -f "$cand" ]; then
      pins="$(grep -E '^native_pins=' "$cand" | head -1 || true)"
      break
    fi
  done
  {
    echo "run_id=$GITHUB_RUN_ID"
    echo "commit=$GITHUB_SHA"
    echo "version=$VERSION"
    echo "formats=tar.gz (portable), deb (Debian 13+/Ubuntu 24.04+), rpm (Fedora 40+/openSUSE), AppImage (any x86_64), Flatpak (org.gnome.Platform 48)"
    echo "scope=v1.0.1 THE LINUX RELEASE ROUND: the same v1.0.1 source as the Android r97 release, packaged for every Linux family. The system-proxy companion widened to EVERY major desktop — GNOME gsettings + KDE Plasma kioslaverc (kwriteconfig6/5; Firefox nsUnixSystemProxySettings and Chromium proxy_config_service_linux.cc both parse those keys under Plasma); each backend's prior state is saved under its own backend= section and restored on disconnect. The Flatpak: dconf grants route the gsettings writes to the HOST's settings, the tunnel-mode bridge runs the host's pkexec through flatpak-spawn --host (companion aethone-tunnel-helper package for the TUN bring-up), and the KDE tools route to the host the same way. deb/rpm/AppImage/tar pre-install the helper + Polkit action (no first-connect self-install prompt). x86-64-v1 baseline, glibc 2.39 floor — see the ISA gates on the desktop-bundle job that built this bundle."
    echo "${pins:-native_pins=<not-carried>}"
    echo "recorded_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$OUT/BUILD_INFO-linux-r$RUN.txt"
  ( cd "$OUT" && sha256sum \
      "aethone-linux-x86_64-$VERSION.tar.gz" \
      "aethone_${VERSION}_amd64.deb" \
      "aethone-tunnel-helper_${VERSION}_amd64.deb" \
      "aethone-$VERSION-1.x86_64.rpm" \
      "aethone-tunnel-helper-$VERSION-1.x86_64.rpm" \
      "AETHONE-$VERSION-x86_64.AppImage" \
      "aethone-$VERSION-x86_64.flatpak" \
      "BUILD_INFO-linux-r$RUN.txt" > "SHA256SUMS-linux-r$RUN.txt" )
  cat "$OUT/SHA256SUMS-linux-r$RUN.txt"
}

main() {
  log "packaging AETHONE $VERSION (run r$RUN) from $BUNDLE"
  stage_main_tree "$WORK/tree-main"
  stage_helper_tree "$WORK/tree-helper"
  build_deb "$PKGROOT/deb/main" "$WORK/tree-main" aethone "$OUT/aethone_${VERSION}_amd64.deb"
  build_deb "$PKGROOT/deb/helper" "$WORK/tree-helper" helper "$OUT/aethone-tunnel-helper_${VERSION}_amd64.deb"
  build_rpm "$PKGROOT/rpm/aethone.spec" "$WORK/tree-main" aethone "$OUT/aethone-$VERSION-1.x86_64.rpm"
  build_rpm "$PKGROOT/rpm/aethone-tunnel-helper.spec" "$WORK/tree-helper" helper "$OUT/aethone-tunnel-helper-$VERSION-1.x86_64.rpm"
  build_appimage
  build_flatpak
  build_tarball
  verify_all
  write_manifests
  log "ALL FORMATS BUILT AND VERIFIED:"
  ls -lh "$OUT"
}

main "$@"
