#!/usr/bin/env python3
"""flatpak_gsettings_bridge_check.py — the v1.0.2 functional gate for the
gsettings HOST bridge of the system-proxy companion.

WHY THIS EXISTS (the v1.0.1 field defect this file pins forever):
  v1.0.1 ran `gsettings` INSIDE the Flatpak sandbox and trusted the
  manifest's dconf grants (talk-name=ca.desrt.dconf + xdg-run/dconf +
  DCONF_USER_CONFIG_DIR) to route the org.gnome.system.proxy writes to the
  host. They provably did not: on a real GNOME desktop (Debian 13, GNOME
  runtime 51) every write exited 0 and vanished — flatpak's D-Bus filtering
  confines sandboxed dconf writers to the app-scoped database — while the
  host's settings never moved and not even an app-scoped dconf file
  appeared. The VPN tunnel came up, the UI reported the companion as set,
  and every proxy-aware app stayed offline. v1.0.2 therefore:

    1. routes every gsettings call through `flatpak-spawn --host
       --clear-env` with an explicitly rebuilt host environment
       (FlatpakHostGSettingsPrefix in desktop_shared/desktop_engine.cpp);
    2. verifies every set with a fresh read-back before reporting success
       (the silent-drop guard in SetSystemProxy);
    3. drops the dead dconf grants from the Flatpak manifest.

WHAT IS PROVEN HERE, against the REAL desktop_engine.cpp (single-TU
harness, no reimplementation):
  * the bridge prefix is built exactly as specified (--clear-env, rebuilt
    user-bus address, host HOME/XDG_CONFIG_HOME, PATH, LANG; the
    /run/user/<uid> fallback when XDG_RUNTIME_DIR is unset);
  * inside a (simulated) sandbox the gsettings calls actually cross a
    flatpak-spawn and the SANDBOX environment does NOT leak into the host
    side (a sentinel var must be absent from the forwarded environment);
  * the v1.0.1 silent drop (set exits 0, nothing changes) is now an
    HONEST ERROR naming the read-back mismatch;
  * the happy path end-to-end: prior host state (the classic v2rayN
    leftovers none/127.0.0.1/10808) is backed up, manual/127.0.0.1/<port>
    lands, and ClearSystemProxy restores the exact prior state;
  * a host with no usable gsettings reports the honest no-backend error;
  * OUTSIDE a sandbox the plain native route is unchanged (no bridge).

The sandbox is simulated with an LD_PRELOAD shim that answers access()
for /.flatpak-info — the exact probe InFlatpakSandbox() makes. The
"host" is a stub flatpak-spawn applying the documented --clear-env +
--env semantics, exec-ing a stateful stub gsettings. Nothing on the
machine running this check is read or written outside the temp dir.

Usage:  python3 scripts/flatpak_gsettings_bridge_check.py   (repo root
or anywhere — paths resolve through this file's location).
"""

import os
import pwd
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE_CPP = os.path.join(REPO_ROOT, "desktop_shared", "desktop_engine.cpp")

STUB_FLATPAK_SPAWN = r"""#!/bin/bash
# The stub "host": records the request, then applies the documented
# flatpak-spawn --host semantics (--clear-env: the child gets ONLY the
# --env values) and runs the command against the stub gsettings.
set -u
LOG="$STUB_SPAWN_LOG"
cmd_start=-1
envs=()
i=0
for arg in "$@"; do
  i=$((i+1))
  printf 'ARG %s\n' "$arg" >> "$LOG"
  if [[ "$arg" == --env=* ]]; then
    envs+=("${arg#--env=}")
    printf 'ENVPASS %s\n' "${arg#--env=}" >> "$LOG"
  fi
  if [[ "$cmd_start" -lt 0 && "$arg" != -* ]]; then
    cmd_start=$i
  fi
done
cmd=("${@:cmd_start}")
exec env -i "${envs[@]}" \
  PATH="$STUB_BIN:/usr/bin:/bin" \
  STUB_STATE="$STUB_STATE" STUB_MODE="$STUB_MODE" STUB_BIN="$STUB_BIN" \
  "${cmd[@]}"
"""

STUB_GSETTINGS = r"""#!/bin/bash
# The stub "host gsettings": a stateful org.gnome.system.proxy over a
# KEY=VALUE file. STUB_MODE=persist (default) | drop (the v1.0.1 silent
# drop: set exits 0 and changes nothing) | absent (no usable gsettings
# at all — every operation fails, e.g. a host without the schema).
set -u
STATE="$STUB_STATE"; MODE="${STUB_MODE:-persist}"
[ "$MODE" = absent ] && exit 1
state_get() {  # $1 = key, $2 = default
  if [ -f "$STATE" ] && v="$(grep -m1 "^$1=" "$STATE" 2>/dev/null)"; then
    printf '%s' "${v#*=}"
  else
    printf '%s' "$2"
  fi
}
state_set() {  # $1 = key, $2 = value
  tmp="$STATE.tmp"
  grep -v "^$1=" "$STATE" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$STATE"
}
op="$1"; schema="$2"; key="$3"; val="${4-}"
case "$schema" in org.gnome.system.proxy|org.gnome.system.proxy.socks) ;; *) exit 1;; esac
case "$key" in mode|host|port|ignore-hosts) ;; *) exit 1;; esac
if [ "$op" = get ]; then
  case "$key" in
    mode) printf "'%s'\n" "$(state_get mode none)";;
    host) printf "'%s'\n" "$(state_get host '')";;
    port) printf '%s\n' "$(state_get port 0)";;
    *) printf '@as []\n';;
  esac
  exit 0
fi
if [ "$op" = set ]; then
  [ "$MODE" = absent ] && exit 1
  [ "$MODE" = drop ] && exit 0     # the v1.0.1 silent drop, faithfully
  state_set "$key" "$val"
  exit 0
fi
exit 1
"""

LD_PRELOAD_SHIM = r"""
/* The sandbox simulation: answer access() exactly where InFlatpakSandbox()
 * probes, pass everything else through to the real implementation. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <unistd.h>
int access(const char *path, int mode) {
  static int (*real_access)(const char *, int) = 0;
  if (real_access == 0) {
    real_access = (int (*)(const char *, int))dlsym(RTLD_NEXT, "access");
  }
  if (path != 0 && strcmp(path, "/.flatpak-info") == 0 && mode == F_OK) {
    return 0;
  }
  return real_access(path, mode);
}
"""

HARNESS_CC = r"""
// The single-TU harness: the REAL desktop_shared/desktop_engine.cpp plus
// a scenario main. Internal-linkage helpers (FlatpakHostGSettingsPrefix,
// GSettings) are reachable because the unnamed namespace sits inside
// namespace aethone in this very TU.
#include "desktop_shared/desktop_engine.cpp"

#include <cstdio>
#include <cstdlib>
#include <string>

int main(int argc, char **argv) {
  if (argc < 2) return 2;
  const std::string cmd = argv[1];
  if (cmd == "prefix") {
    std::fputs(aethone::FlatpakHostGSettingsPrefix().c_str(), stdout);
    return 0;
  }
  if (cmd == "get-mode") {
    bool ok = false;
    const std::string out =
        aethone::GSettings("get org.gnome.system.proxy mode", &ok);
    std::printf("ok=%d out=%s", ok ? 1 : 0, out.c_str());
    return 0;
  }
  if (cmd == "set") {
    if (argc < 3) return 2;
    const std::string err = aethone::SetSystemProxy(std::atoi(argv[2]));
    std::printf("result=[%s]\n", err.c_str());
    return err.empty() ? 0 : 1;
  }
  if (cmd == "clear") {
    const std::string err = aethone::ClearSystemProxy();
    std::printf("result=[%s]\n", err.c_str());
    return err.empty() ? 0 : 1;
  }
  return 2;
}
"""


def log(msg: str) -> None:
    print(f"  {msg}")


def die(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def run_harness(harness, work, *cmd, sandbox=False, xdg_runtime="/run/user/4242",
                stub_mode="persist", state_file=None, env_extra=None):
    """One harness invocation. sandbox=True flips InFlatpakSandbox() via the
    LD_PRELOAD shim, exactly what a Flatpak run would look like to the code."""
    env = dict(os.environ)
    env.pop("XDG_CURRENT_DESKTOP", None)
    env.pop("DESKTOP_SESSION", None)
    env.pop("KDE_SESSION_VERSION", None)
    env["PATH"] = os.path.join(work, "bin") + ":/usr/bin:/bin"
    env["XDG_DATA_HOME"] = os.path.join(work, "data")
    if xdg_runtime is not None:
        env["XDG_RUNTIME_DIR"] = xdg_runtime
    else:
        env.pop("XDG_RUNTIME_DIR", None)
    env["STUB_BIN"] = os.path.join(work, "bin")
    env["STUB_STATE"] = state_file or os.path.join(work, "state.gsettings")
    env["STUB_MODE"] = stub_mode
    spawn_log = os.path.join(work, "spawn.log")
    if os.path.exists(spawn_log):
        os.remove(spawn_log)
    env["STUB_SPAWN_LOG"] = spawn_log
    if sandbox:
        env["LD_PRELOAD"] = os.path.join(work, "fakeflatpak.so")
        env["AETHONE_SANDBOX_SENTINEL"] = "must-not-leak"
    else:
        env.pop("LD_PRELOAD", None)
    if env_extra:
        env.update(env_extra)
    proc = subprocess.run([harness, *cmd], capture_output=True, text=True,
                          env=env, timeout=120)
    return proc, spawn_log


def read_state(path):
    state = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                if "=" in line:
                    k, v = line.rstrip("\n").split("=", 1)
                    state[k] = v
    return state


def main() -> None:
    if not os.path.isfile(ENGINE_CPP):
        die(f"desktop_engine.cpp not found at {ENGINE_CPP}")
    for tool in ("g++", "gcc"):
        if shutil.which(tool) is None:
            die(f"{tool} is required")

    work = tempfile.mkdtemp(prefix="aethone-gsettings-bridge-")
    try:
        # ---- stage the stubs, the shim and the harness --------------------
        bin_dir = os.path.join(work, "bin")
        os.makedirs(bin_dir)
        stub_spawn = os.path.join(bin_dir, "flatpak-spawn")
        with open(stub_spawn, "w", encoding="utf-8") as fh:
            fh.write(STUB_FLATPAK_SPAWN)
        os.chmod(stub_spawn, 0o755)
        stub_gs = os.path.join(bin_dir, "gsettings")
        with open(stub_gs, "w", encoding="utf-8") as fh:
            fh.write(STUB_GSETTINGS)
        os.chmod(stub_gs, 0o755)

        shim_src = os.path.join(work, "fakeflatpak.c")
        with open(shim_src, "w", encoding="utf-8") as fh:
            fh.write(LD_PRELOAD_SHIM)
        subprocess.run(["gcc", "-shared", "-fPIC", "-o",
                        os.path.join(work, "fakeflatpak.so"), shim_src, "-ldl"],
                       check=True, capture_output=True)

        harness_src = os.path.join(work, "harness.cc")
        with open(harness_src, "w", encoding="utf-8") as fh:
            fh.write(HARNESS_CC)
        harness = os.path.join(work, "harness")
        build = subprocess.run(
            ["g++", "-std=c++17", "-Wall", "-Wextra", "-I", REPO_ROOT,
             "-I", os.path.join(REPO_ROOT, "native", "zeptun", "include"),
             harness_src, "-o", harness, "-lpthread", "-ldl"],
            capture_output=True, text=True)
        if build.returncode != 0:
            die("harness build failed (the engine TU must compile whole):\n"
                + build.stderr)
        log("harness built: the REAL desktop_engine.cpp, whole")

        home = pwd.getpwuid(os.getuid()).pw_dir

        # ---- 1. the bridge prefix construction ----------------------------
        proc, _ = run_harness(harness, work, "prefix", sandbox=False)
        prefix = proc.stdout
        must = [
            "flatpak-spawn --host --clear-env",
            "--env=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "--env=HOME='" + home + "'",
            "--env=XDG_CONFIG_HOME='" + home + "/.config'",
            "--env=XDG_RUNTIME_DIR='/run/user/4242'",
            "--env=DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/4242/bus'",
        ]
        for frag in must:
            if frag not in prefix:
                die(f"bridge prefix missing [{frag}]: got [{prefix}]")
        log("prefix: --clear-env + rebuilt host env (bus/user-bus path) OK")

        proc, _ = run_harness(harness, work, "prefix", sandbox=False,
                              xdg_runtime=None)
        if f"--env=XDG_RUNTIME_DIR='/run/user/{os.getuid()}'" not in proc.stdout \
            or f"unix:path=/run/user/{os.getuid()}/bus" not in proc.stdout:
            die("bridge prefix /run/user/<uid> fallback broken: "
                + proc.stdout)
        log("prefix: /run/user/<uid> fallback when XDG_RUNTIME_DIR unset OK")

        # ---- 2. the sandbox route + the no-leak proof ---------------------
        state_a = os.path.join(work, "state.a")
        proc, spawn_log = run_harness(harness, work, "get-mode", sandbox=True,
                                      state_file=state_a)
        if "ok=1 out='none'" not in proc.stdout:
            die(f"sandboxed get did not cross the bridge: {proc.stdout!r} "
                f"stderr={proc.stderr!r}")
        if not os.path.exists(spawn_log):
            die("the sandboxed gsettings call never went through flatpak-spawn")
        spawn_txt = open(spawn_log, encoding="utf-8").read()
        if "must-not-leak" in spawn_txt:
            die("the SANDBOX environment leaked into the host side "
                "(--clear-env discipline broken)")
        for frag in ("--clear-env", "--host",
                     "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/4242/bus",
                     "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"):
            if frag not in spawn_txt:
                die(f"the bridged flatpak-spawn invocation lacks [{frag}]:\n"
                    + spawn_txt)
        if "XDG_CONFIG_HOME=" in spawn_txt and "/.var/app/" in spawn_txt:
            die("the app-scoped XDG_CONFIG_HOME leaked into the host env:\n"
                + spawn_txt)
        log("route: gsettings crossed flatpak-spawn --host, clean env, "
            "sandbox sentinel absent OK")

        # ---- 3. the v1.0.1 silent drop is now an honest error -------------
        state_b = os.path.join(work, "state.b")
        proc, _ = run_harness(harness, work, "set", "1819", sandbox=True,
                              stub_mode="drop", state_file=state_b)
        if proc.returncode == 0 or "did not stick" not in proc.stdout:
            die(f"the silent drop must be an HONEST read-back error, got: "
                f"rc={proc.returncode} {proc.stdout!r}")
        dropped = read_state(state_b)
        if dropped.get("mode") == "manual":
            die("drop mode unexpectedly wrote")
        backup = os.path.join(work, "data", "aethone",
                              "system-proxy-backup.txt")
        if not os.path.exists(backup):
            die("the prior state was not backed up before the writes")
        log("silent-drop guard: set-then-vanish now fails honestly, "
            "prior state still backed up OK")

        # ---- 4. the happy path end-to-end through the bridge --------------
        shutil.rmtree(os.path.join(work, "data"), ignore_errors=True)
        state_c = os.path.join(work, "state.c")
        with open(state_c, "w", encoding="utf-8") as fh:  # v2rayN leftovers
            fh.write("mode=none\nhost=127.0.0.1\nport=10808\n")
        proc, _ = run_harness(harness, work, "set", "1819", sandbox=True,
                              stub_mode="persist", state_file=state_c)
        if proc.returncode != 0:
            die(f"happy path failed: {proc.stdout!r} stderr={proc.stderr!r}")
        final = read_state(state_c)
        if final.get("mode") != "manual" or final.get("host") != "127.0.0.1" \
                or final.get("port") != "1819":
            die(f"the host state was not set to manual/127.0.0.1/1819: {final}")
        with open(backup, encoding="utf-8") as fh:
            saved = fh.read()
        for line in ("backend=gsettings", "mode=none", "socks-host=127.0.0.1",
                     "socks-port=10808"):
            if line not in saved:
                die(f"backup missing [{line}]:\n{saved}")
        proc, _ = run_harness(harness, work, "clear", sandbox=True,
                              stub_mode="persist", state_file=state_c)
        if proc.returncode != 0:
            die(f"clear failed: {proc.stdout!r}")
        restored = read_state(state_c)
        if restored.get("mode") != "none" or restored.get("host") != "127.0.0.1" \
                or restored.get("port") != "10808":
            die(f"the prior host state was not restored: {restored}")
        if os.path.exists(backup):
            die("the backup file survived the restore")
        log("happy path: none/127.0.0.1/10808 backed up, manual/1819 set "
            "via the bridge, restore exact OK")

        # ---- 5. the native route is unchanged (no bridge) ------------------
        state_d = os.path.join(work, "state.d")
        proc, spawn_log = run_harness(harness, work, "get-mode", sandbox=False,
                                      state_file=state_d)
        if "ok=1 out='none'" not in proc.stdout:
            die(f"native gsettings route broken: {proc.stdout!r}")
        if os.path.exists(spawn_log):
            die("native route unexpectedly crossed a flatpak-spawn bridge")
        log("native route: plain gsettings, no bridge OK")

        # ---- 6. a host without a usable gsettings fails honestly ----------
        shutil.rmtree(os.path.join(work, "data"), ignore_errors=True)
        state_e = os.path.join(work, "state.e")
        proc, _ = run_harness(harness, work, "set", "1819", sandbox=True,
                              stub_mode="absent", state_file=state_e)
        if proc.returncode == 0 or "no supported system-proxy backend" \
                not in proc.stdout:
            die(f"a gsettings-less host must report the honest no-backend "
                f"error, got: {proc.stdout!r}")
        log("no-backend host: honest error OK")

        print("FLATPAK GSETTINGS BRIDGE CHECK PASS "
              "(prefix + bridge route + no-leak + silent-drop guard + "
              "backup/restore + native route + honest no-backend)")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
