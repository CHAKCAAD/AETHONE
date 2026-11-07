// AETHONE desktop shared engine layer (v4.36) — the C++ twin of the Android
// Kotlin surface, used by BOTH desktop runners:
//
//   * linux/runner/engine_channel_linux.cc   (GTK, FlMethodChannel)
//   * windows/runner/engine_channel_windows.cpp (Win32, flutter::MethodChannel)
//
// Everything platform-sensitive (path resolution, the zeptun TOML document,
// the bounded core-log capture, dlopen/LoadLibrary of the two engines) lives
// HERE so the two glue files stay thin. The surface mirrors
// android/app/src/main/kotlin/.../MainActivity.kt + AethoneVpnService.kt
// method-for-method so lib/connection/platform_engine_adapter.dart runs
// UNCHANGED on desktop — the whole point of the desktop round: same look,
// same walk, same honest failures.
//
// Frozen pins (unchanged, N1/N8): aether @ d58f9d56 (libaether.so / aether.dll
// via its C API, called from DART through dart:ffi), zeptun @ 08a1ab05 (this
// layer: zeptun_create_from_toml / _start / _stats / _stop / _destroy through
// the vendored native/zeptun/include/zeptun.h), lyrebird fc105a03 + the
// psiphon fork 2956a96 (child cores exec'd by the aether core itself).
#pragma once

#include <cstdint>
#include <string>

namespace aethone {

// ---- resolved per-platform paths (computed once, then cached) ----
struct DesktopPaths {
  std::string exeDir;       // directory of the running executable
  std::string filesDir;     // writable app-data dir (created on first use)
  std::string aetherLib;    // aether cdylib  (Linux lib/libaether.so | aether.dll)
  std::string zeptunLib;    // zeptun shared  (Linux lib/libzeptun.so | zeptun.dll)
  std::string lyrebirdBin;  // child cores, beside the executable
  std::string psiphonBin;   // (lyrebird / lyrebird.exe, psiphon / psiphon.exe)
  std::string helperBin;    // Linux: the bundled privilege helper ("" elsewhere)
  std::string helperPolicy; // Linux: its Polkit action file ("" elsewhere)
};

// Lazily computes and caches the platform paths. Never returns empty strings.
const DesktopPaths& Paths();

// ---- the aether cdylib preload ------------------------------------------
// Preloads the embedded core by ABSOLUTE path (RTLD_GLOBAL on Linux) so the
// Dart side's `DynamicLibrary.open('libaether.so')` / `('aether.dll')`
// resolves to THIS already-loaded object (Linux dlopen has no exe-dir search
// and LD_LIBRARY_PATH cannot be changed at runtime; Windows finds aether.dll
// in the exe dir natively, so this is a Windows-side no-op returning "" when
// the file is absent). Returns an error string, empty on success.
std::string PreloadAetherLibrary();

// ---- the zeptun library handle (dlopen'd once, kept for the process) ----
// Returns an empty string when the library is missing (the honest
// `libraryMissing` face surfaces through startVpn's error).
std::string LoadZeptunLibrary();
bool ZeptunLibraryLoaded();

// ---- bounded core-log capture (MainActivity.installCoreLogRedirect twin) ----
// Call once BEFORE the Flutter engine starts. Captures the process
// stdout+stderr (the embedded Rust core logs there) into
// <filesDir>/logs/core-log.txt, rotating at 1 MiB into core-log.1.txt
// (one previous generation kept — 2 MiB hard ceiling, exactly the Kotlin
// budget). Every process start wipes BOTH generations (the owner's v4.34
// decree: the log must not survive the closed app).
void InstallCoreLogCapture();
// The bounded tail across the current file + its one previous rotation.
std::string ReadCoreLogTail(int tailBytes, int64_t* totalBytesOut);
// Instant deletion + the single-writer reader reopens a fresh file on its
// next chunk (same discipline as the Kotlin side).
void ClearCoreLog();

// ---- process-durable aether job id (the Kotlin companion twin) ----
void SetCoreJob(int64_t job);
int64_t GetCoreJob();  // 0 = none (the Kotlin side uses null; 0 is never a job id)
void ClearCoreJob();

// ---- zeptun tunnel lifecycle (AethoneVpnService twin) ----

// The startVpn outcome. kOk means the tunnel is UP (zeptun_start returned 0);
// the glue layer then emits the `up` event. kStaleSession mirrors the Kotlin
// straggler gate: a start superseded by a newer stop refuses to establish.
// kError carries the honest reason string for the PlatformException.
enum class TunnelStartKind { kOk, kStaleSession, kError };

struct TunnelStartResult {
  TunnelStartKind kind;
  std::string reason;   // kError: "zeptun-start-failed:rc=N (<strerror>)" etc.
};

// Builds the desktop TOML document and brings the engine up. The document
// mirrors the Kotlin AethoneVpnService TOML field-for-field where the desktop
// preset allows (preset desktop; tun 172.19.0.1/30; socks5 handler on
// 127.0.0.1:port; [dns] fake_ip; the v4.31b lesson holds: udp is the bare
// bool `false`, NEVER the string "disabled"). The desktop-only route section:
//   * Linux   — exclude_uid = [<uid>]: the app's own uid (aether in-process
//     + the child cores it spawns) bypasses the tunnel, everything else is
//     routed in (the uid-range twin of Android's addDisallowedApplication).
//   * Windows — exclude = the Cloudflare WARP pools (aether's own prober
//     CIDR set, src/prober.rs at the frozen pin) so the WARP-leg dials keep
//     the physical path instead of looping the TUN back into itself.
// Starts (or restarts) the zeptun tunnel toward the SOCKS5 listener at
// `port`. `tcpOnly` disables the SOCKS UDP ASSOCIATE (the tor/psiphon
// family); `socksStrict` forces a fully sequential SOCKS5 client
// (pipeline = false + optimistic_data = false) for the psiphon family,
// whose goptlib listener rejects pipelined bytes — the v4.38 data-path
// fix (see BuildZeptunToml and LINUX_RUNTIME_AND_TUNNEL_FIX_REPORT.md).
TunnelStartResult StartTunnel(int port, int session, bool tcpOnly,
                               bool socksStrict);

// The hardened stop (requestStop twin): generation bump + synchronous
// teardown. Returns the session id the `down` event should echo.
int StopTunnel();

// ---- v4.37: the Linux privilege bring-up (Polkit helper) ----------------
//
// On Linux as a NORMAL user, zeptun's TUN/link/route setup needs
// CAP_NET_ADMIN — the direct StartTunnel then fails with
// `zeptun-start-failed:rc=-3 (permission denied)` (the owner's report).
// The fix: a tiny root helper (linux/helper/aethone_tunnel_helper.cc)
// does ONLY those network operations, launched per connection via pkexec.
//
// StartTunnelAsync ACCEPTS the request (returns immediately — the walk's
// tunnelUp budget covers the Polkit dialog) and completes on the event
// sink, exactly like Android's startForegroundService → EngineBridge.emit
// model. The sink is invoked on the WORKER thread; the glue layer marshals
// it onto the platform main loop.
struct TunnelEvent {
  bool up;             // true: the tunnel is UP (zeptun running on the
                       // helper-provided, verified TUN); false: bring-up
                       // failed (or was superseded) — reason carries why.
  int port;
  int session;
  std::string reason;  // kError-class reasons, verbatim for the UI
};

using TunnelEventSink = void (*)(void* ctx, const TunnelEvent& event);

// Installs the sink (once). ctx is passed back verbatim.
void SetTunnelEventSink(TunnelEventSink sink, void* ctx);

// True when THIS build takes the helper path for tunnels: Linux, not root,
// and the runner chose the helper mode (see StartTunnelAsync).
bool TunnelPrivilegeViaHelper();

// The async bring-up. Root/Windows callers keep the synchronous StartTunnel
// (the helper adds nothing there); Linux normal-user callers use this.
void StartTunnelAsync(int port, int session, bool tcpOnly, bool socksStrict);

// ---- v4.37: the through-tunnel data-path verification (requirement D) ----
//
// The walk's SOCKS probe talks to 127.0.0.1:<port> DIRECTLY — it proves the
// CORE path, not the TUN path. When the helper owns the tunnel (normal
// user), this asks the helper (uid 0, NOT excluded by the uid rule) to make
// a REAL request THROUGH the tunnel: resolve → TUN → zeptun → SOCKS5 →
// aether → internet. The walk reports Connected only after this passes.
struct TunnelPathProbe {
  bool attempted;     // false: no helper-backed tunnel (root/direct mode) —
                      // the local SOCKS probe remains the only gate there.
  bool verified;      // the data path really passed traffic
  int64_t elapsedMs;  // first-byte RTT when verified
  std::string detail; // human-readable outcome (never secrets)
};

// SLOW (up to ~20 s): runs on a worker thread; the glue layer must not call
// it on the platform main thread.
TunnelPathProbe VerifyTunnelPath();

struct TunnelCounters {
  bool running;
  int port;                // 0 = no live tunnel
  int64_t rxBytes;         // -1 when not running (the Kotlin face)
  int64_t txBytes;
};

/// The live counters (running flag + port + rx/tx bytes). Named Read* to
/// keep the struct type and the accessor from colliding in C++ lookup.
TunnelCounters ReadTunnelCounters();

// ---- v4.39: the Linux root-from-start model (the owner's decree) --------
//
// The owner's decree (delivered in Persian, 2026-11-07): the tunnel must
// not be the only thing that runs elevated — the WHOLE app must run as
// root from launch, so it can bring the TUN up AND spawn every engine it
// needs in the background by itself, with no per-action prompts. (The
// decree's own wording is recorded in linux/runner/main.cc — this header
// compiles on MSVC too, where the sources stay pure ASCII.)
//
// ElevateAtStartup() is the FIRST statement of linux/runner/main.cc —
// before the log capture, before GTK, before any engine work. When the
// session can authenticate, the process relaunches as root through
// `pkexec env <session vars> <exe>` (ONE polkit prompt at launch; /usr/bin/
// env is root-owned, so pkexec's refusal to execute user-writable bundle
// paths does not apply — the same proven bootstrap the v4.37 helper uses).
// Returns true when an elevated child ran to completion: main() must then
// exit with *exit_code immediately. Returns false when no attempt was
// made or it was declined (headless CI launch, pkexec missing, password
// canceled) — the process continues in place and the v4.37 helper path
// remains the unprivileged fallback for tunnels.
bool ElevateAtStartup(int* exit_code);

// The root instance's one-time (idempotent, best-effort) system
// integration, called after the log capture so the outcome lands in the
// captured core log: the hicolor app icon (the owner's mark on white) and
// the .desktop menu entry. Exec always points at THIS bundle's current
// location, so a moved bundle self-heals on its next root launch.
// Windows keeps the embedded-resource model and needs none of this.
void EnsureDesktopIntegration();

}  // namespace aethone
