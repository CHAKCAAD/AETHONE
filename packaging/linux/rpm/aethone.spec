# aethone.spec — the v1.0.1 rpm of the AETHONE desktop app.
# Built by packaging/linux/build_packages.sh from the same staged tree as
# the .deb (one build, every format). The spec is minimal on purpose: the
# file tree is staged verbatim under %{buildroot} by the build script, so
# there is no %build/%install phase at all.
Name: aethone
Version: __VERSION__
Release: 1
Summary: Cross-platform VPN client (MASQUE, WireGuard, VLESS-WS, Tor, Psiphon)
License: AGPL-3.0-only
URL: https://github.com/CHAKCAAD/AETHONE
Packager: AETHONE Project <aethone@users.noreply.github.com>
AutoReqProv: no
Requires: gtk3
Recommends: polkit
BuildArch: x86_64

%description
AETHONE routes the whole device or proxy-aware apps through Aether
(WARP-class core) and zeptun (userspace TUN router) with MASQUE, WireGuard,
VLESS-WS, Tor and Psiphon protocols.

While the tunnel is up the system proxy points at the same local SOCKS5
listener (GNOME gsettings + KDE kioslaverc), so browsers ride the tunnel
too; the state is restored on disconnect.

Built at the x86-64-v1 baseline against glibc 2.39 — Fedora 40+, openSUSE
Leap 16 / Tumbleweed and newer rpm-family releases.

%files
"/usr/bin/aethone"
"/usr/lib/aethone/"
"/usr/libexec/aethone-tunnel-helper"
"/usr/share/applications/com.chakcaad.aethone.desktop"
"/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy"
"/usr/share/icons/hicolor/16x16/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/24x24/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/32x32/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/48x48/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/64x64/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/96x96/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/128x128/apps/com.chakcaad.aethone.png"
"/usr/share/icons/hicolor/256x256/apps/com.chakcaad.aethone.png"
