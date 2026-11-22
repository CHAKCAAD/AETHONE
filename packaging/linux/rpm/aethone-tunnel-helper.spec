# aethone-tunnel-helper.spec — the companion rpm for the AETHONE Flatpak
# (the host-side TUN bring-up helper + its polkit action).
Name: aethone-tunnel-helper
Version: __VERSION__
Release: 1
Summary: Privileged tunnel helper for the AETHONE Flatpak
License: AGPL-3.0-only
URL: https://github.com/CHAKCAAD/AETHONE
Packager: AETHONE Project <aethone@users.noreply.github.com>
AutoReqProv: no
Requires: polkit
BuildArch: x86_64

%description
The TUN bring-up half of AETHONE's tunnel mode: pkexec-launched, serves
exactly one client over a user-owned Unix socket, hands the verified TUN
fd back to the app and tears everything down on disconnect.

This companion package exists for the FLATPAK build of AETHONE, where the
sandbox cannot self-install the helper: install it on the host once and
the Flatpak's tunnel mode works with the normal polkit prompt. The
deb/rpm/AppImage/tar releases ship the helper inside the app bundle and
do NOT need this package.

%files
"/usr/libexec/aethone-tunnel-helper"
"/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy"
