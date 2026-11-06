cmake_minimum_required(VERSION 3.13)

# aethone-tunnel-helper — the Linux privilege helper (v4.37 runtime round).
# A tiny standalone executable (no Flutter, no GTK): it performs ONLY the
# elevated tunnel operations (TUN + netlink routes/rules + resolved DNS
# delegation) on behalf of the unprivileged app, launched per connection
# through pkexec. See linux/helper/aethone_tunnel_helper.cc for the design.
#
# Built as part of the normal `flutter build linux` run; installed into the
# bundle root beside the main binary so the app's bootstrap step can copy it
# to /usr/libexec (pkexec refuses to execute binaries from user-writable
# bundle directories).
add_executable(aethone-tunnel-helper "aethone_tunnel_helper.cc")

apply_standard_settings(aethone-tunnel-helper)

# Same hardened, warning-free surface as the runner (the v4.36n build
# discipline; -march=x86-64 arrives from the project-scope options).
target_compile_features(aethone-tunnel-helper PUBLIC cxx_std_17)
