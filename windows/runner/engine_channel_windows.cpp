// engine_channel_windows.cpp — the `aethone/engine` MethodChannel for the
// Win32 runner (v4.36 desktop round). One thin adapter over desktop_shared:
// the exact surface MainActivity.kt hosts on Android, method for method, so
// lib/connection/platform_engine_adapter.dart runs unchanged.
//
// Registered from FlutterWindow::OnCreate right after RegisterPlugins() —
// the same ordering as Android's configureFlutterEngine.
//
// v4.36h: rewritten for the 3.47 C++ embedding. The old convenience accessors
// (IsInt/IntValue/IsBool/BoolValue/IsMap) are gone from EncodableValue, and
// the local `EncodableMap = std::map<std::string, …>` alias never matched the
// engine's `EncodableMap = std::map<EncodableValue, EncodableValue>` — so the
// file had never actually compiled on a hosted runner. The engine headers
// bless exactly one access pattern (see encodable_value.h):
//   std::holds_alternative<T>(value) / std::get<T>(value)
// LongValue() covers both int32_t and int64_t (Dart ints arrive as either).
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <variant>

#include "desktop_shared/desktop_engine.h"
#include "engine_channel_windows.h"

namespace {

flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;

// Map lookup by string key — EncodableMap keys are EncodableValue, so the
// key is constructed rather than converted.
const flutter::EncodableValue* ArgValue(const flutter::EncodableMap& args,
                                        const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  return it == args.end() ? nullptr : &it->second;
}

int ArgInt(const flutter::EncodableMap& args, const char* key, int fallback) {
  const flutter::EncodableValue* v = ArgValue(args, key);
  if (v == nullptr) return fallback;
  if (std::holds_alternative<int32_t>(*v) ||
      std::holds_alternative<int64_t>(*v)) {
    return static_cast<int>(v->LongValue());
  }
  return fallback;
}

bool ArgBool(const flutter::EncodableMap& args, const char* key,
             bool fallback) {
  const flutter::EncodableValue* v = ArgValue(args, key);
  if (v == nullptr) return fallback;
  if (std::holds_alternative<bool>(*v)) return std::get<bool>(*v);
  return fallback;
}

// Outgoing map setters (EncodableValue's conversion constructors are
// explicit in 3.47 — every value is direct-initialized with its exact type).
void SetStr(flutter::EncodableMap& m, const char* key, std::string value) {
  m[flutter::EncodableValue(key)] =
      flutter::EncodableValue(std::move(value));
}
void SetInt(flutter::EncodableMap& m, const char* key, int64_t value) {
  m[flutter::EncodableValue(key)] = flutter::EncodableValue(value);
}
void SetBool(flutter::EncodableMap& m, const char* key, bool value) {
  m[flutter::EncodableValue(key)] = flutter::EncodableValue(value);
}

// Emits one tunnel event (the EngineBridge.emit twin). All handlers run on
// the Win32 message loop thread — the same single-thread discipline.
void Emit(const char* event, int port, const char* reason, int session) {
  if (g_channel == nullptr) return;
  flutter::EncodableMap args;
  SetStr(args, "event", event);
  SetInt(args, "port", port);
  if (reason != nullptr) {
    SetStr(args, "reason", reason);
  }
  SetInt(args, "session", session);
  g_channel->InvokeMethod(
      "onTunnelEvent",
      std::make_unique<flutter::EncodableValue>(args));
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& name = call.method_name();
  const flutter::EncodableValue* raw_args = call.arguments();
  flutter::EncodableMap args;
  if (raw_args != nullptr &&
      std::holds_alternative<flutter::EncodableMap>(*raw_args)) {
    args = std::get<flutter::EncodableMap>(*raw_args);
  }

  if (name == "paths") {
    const aethone::DesktopPaths& p = aethone::Paths();
    flutter::EncodableMap out;
    SetStr(out, "filesDir", p.filesDir);
    // The Dart layer builds `<nativeLibraryDir>/liblyrebird.so` when the
    // explicit paths are absent — keep pointing it somewhere honest even
    // though the desktop always answers the explicit fields below.
    SetStr(out, "nativeLibraryDir", p.exeDir);
    SetStr(out, "lyrebirdPath", p.lyrebirdBin);
    SetStr(out, "psiphonPath", p.psiphonBin);
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "prepareVpn") {
    // Desktop: no OS consent dialog — privilege is enforced at TUN open and
    // surfaces as the honest zeptun error when elevated rights are missing.
    flutter::EncodableMap out;
    SetBool(out, "needsPermission", false);
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "startVpn") {
    const int port = ArgInt(args, "port", 1819);
    const int session = ArgInt(args, "session", 0);
    const bool tcpOnly = ArgBool(args, "tcpOnly", false);
    const aethone::TunnelStartResult res =
        aethone::StartTunnel(port, session, tcpOnly);
    switch (res.kind) {
      case aethone::TunnelStartKind::kOk:
        result->Success();
        Emit("up", port, nullptr, session);
        return;
      case aethone::TunnelStartKind::kStaleSession:
        // The straggler gate: a start superseded by a newer stop refuses to
        // establish (the Kotlin twin) — reported as a down event, never up.
        result->Success();
        Emit("down", 0, res.reason.c_str(), session);
        return;
      case aethone::TunnelStartKind::kError:
        result->Error("tunnelStartFailed", res.reason);
        return;
    }
    return;
  }
  if (name == "stopVpn") {
    const int session = aethone::StopTunnel();
    result->Success();
    Emit("down", 0, "destroy", session);
    return;
  }
  if (name == "vpnStatus") {
    const aethone::TunnelCounters c = aethone::ReadTunnelCounters();
    flutter::EncodableMap out;
    SetBool(out, "running", c.running);
    if (c.running) {
      SetInt(out, "port", c.port);
    } else {
      out[flutter::EncodableValue("port")] = flutter::EncodableValue();
    }
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "zeptunCounters") {
    const aethone::TunnelCounters c = aethone::ReadTunnelCounters();
    flutter::EncodableMap out;
    SetInt(out, "rxBytes", static_cast<int64_t>(c.rxBytes));
    SetInt(out, "txBytes", static_cast<int64_t>(c.txBytes));
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "setCoreJob") {
    aethone::SetCoreJob(ArgInt(args, "job", 0));
    result->Success();
    return;
  }
  if (name == "getCoreJob") {
    flutter::EncodableMap out;
    SetInt(out, "job", aethone::GetCoreJob());
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "clearCoreJob") {
    aethone::ClearCoreJob();
    result->Success();
    return;
  }
  if (name == "startCoreHold") {
    // Desktop: the Flutter window IS the process — while it stays open the
    // in-process core keeps serving (the Android CoreHoldService exists only
    // because Android may kill the backgrounded process). Honest no-op.
    result->Success();
    return;
  }
  if (name == "stopCoreHold") {
    result->Success();
    return;
  }
  if (name == "coreHoldStatus") {
    flutter::EncodableMap out;
    SetBool(out, "running", false);
    out[flutter::EncodableValue("port")] = flutter::EncodableValue();
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "readCoreLog") {
    const int tail = ArgInt(args, "tail", 64 * 1024);
    int64_t total = 0;
    const std::string text = aethone::ReadCoreLogTail(tail, &total);
    flutter::EncodableMap out;
    SetStr(out, "text", text);
    SetInt(out, "totalBytes", total);
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "clearCoreLog") {
    aethone::ClearCoreLog();
    result->Success();
    return;
  }
  result->NotImplemented();
}

}  // namespace

namespace aethone {

void RegisterEngineChannel(FlutterDesktopPluginRegistrarRef registrar) {
  if (registrar == nullptr) return;
  // v4.36h: the 3.47 embedding vends typed registrars through the manager —
  // the exact pattern the pinned url_launcher_windows plugin uses
  // (engine()->registrar() was removed from the embedding).
  flutter::PluginRegistrar* plugin_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrar>(registrar);
  // A static unique_ptr parks the channel for the life of the process (the
  // runner never tears it down before exit — Unregister only nulls the
  // emitting pointer).
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      parked;
  parked = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      plugin_registrar->messenger(), "aethone/engine",
      &flutter::StandardMethodCodec::GetInstance());
  parked->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  g_channel = parked.get();
}

void UnregisterEngineChannel() {
  // The channel lives with the process; only the emitting pointer is nulled.
  g_channel = nullptr;
}

}  // namespace aethone
