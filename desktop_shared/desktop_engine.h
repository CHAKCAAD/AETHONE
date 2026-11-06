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
TunnelStartResult StartTunnel(int port, int session, bool tcpOnly);

// The hardened stop (requestStop twin): generation bump + synchronous
// teardown. Returns the session id the `down` event should echo.
int StopTunnel();

struct TunnelCounters {
  bool running;
  int port;                // 0 = no live tunnel
  int64_t rxBytes;         // -1 when not running (the Kotlin face)
  int64_t txBytes;
};

/// The live counters (running flag + port + rx/tx bytes). Named Read* to
/// keep the struct type and the accessor from colliding in C++ lookup.
TunnelCounters ReadTunnelCounters();

}  // namespace aethone
