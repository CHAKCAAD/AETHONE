// engine_channel_windows.cpp — the `aethone/engine` MethodChannel for the
// Win32 runner (v4.36 desktop round). One thin adapter over desktop_shared:
// the exact surface MainActivity.kt hosts on Android, method for method, so
// lib/connection/platform_engine_adapter.dart runs unchanged.
//
// Registered from FlutterWindow::OnCreate right after RegisterPlugins() —
// the same ordering as Android's configureFlutterEngine.
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <string>

#include "desktop_shared/desktop_engine.h"
#include "engine_channel_windows.h"

namespace {

using EncodableMap =
    std::map<std::string, flutter::EncodableValue>;

flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;

int ArgInt(const EncodableMap& args, const char* key, int fallback) {
  const auto it = args.find(key);
  if (it == args.end() || !it->second.IsInt()) return fallback;
  return static_cast<int>(it->second.IntValue());
}

bool ArgBool(const EncodableMap& args, const char* key, bool fallback) {
  const auto it = args.find(key);
  if (it == args.end() || !it->second.IsBool()) return fallback;
  return it->second.BoolValue();
}

// Emits one tunnel event (the EngineBridge.emit twin). All handlers run on
// the Win32 message loop thread — the same single-thread discipline.
void Emit(const char* event, int port, const char* reason, int session) {
  if (g_channel == nullptr) return;
  EncodableMap args;
  args["event"] = flutter::EncodableValue(std::string(event));
  args["port"] = flutter::EncodableValue(static_cast<int64_t>(port));
  if (reason != nullptr) {
    args["reason"] = flutter::EncodableValue(std::string(reason));
  }
  args["session"] = flutter::EncodableValue(static_cast<int64_t>(session));
  g_channel->InvokeMethod(
      "onTunnelEvent",
      std::make_unique<flutter::EncodableValue>(args));
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& name = call.method_name();
  const flutter::EncodableValue* raw_args = call.arguments();
  EncodableMap args;
  if (raw_args != nullptr && raw_args->IsMap()) {
    args = std::get<EncodableMap>(*raw_args);
  }

  if (name == "paths") {
    const aethone::DesktopPaths& p = aethone::Paths();
    EncodableMap out;
    out["filesDir"] = flutter::EncodableValue(p.filesDir);
    // The Dart layer builds `<nativeLibraryDir>/liblyrebird.so` when the
    // explicit paths are absent — keep pointing it somewhere honest even
    // though the desktop always answers the explicit fields below.
    out["nativeLibraryDir"] = flutter::EncodableValue(p.exeDir);
    out["lyrebirdPath"] = flutter::EncodableValue(p.lyrebirdBin);
    out["psiphonPath"] = flutter::EncodableValue(p.psiphonBin);
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "prepareVpn") {
    // Desktop: no OS consent dialog — privilege is enforced at TUN open and
    // surfaces as the honest zeptun error when elevated rights are missing.
    EncodableMap out;
    out["needsPermission"] = flutter::EncodableValue(false);
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
    EncodableMap out;
    out["running"] = flutter::EncodableValue(c.running);
    out["port"] = c.running
                      ? flutter::EncodableValue(static_cast<int64_t>(c.port))
                      : flutter::EncodableValue();
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "zeptunCounters") {
    const aethone::TunnelCounters c = aethone::ReadTunnelCounters();
    EncodableMap out;
    out["rxBytes"] = flutter::EncodableValue(static_cast<int64_t>(c.rxBytes));
    out["txBytes"] = flutter::EncodableValue(static_cast<int64_t>(c.txBytes));
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "setCoreJob") {
    aethone::SetCoreJob(ArgInt(args, "job", 0));
    result->Success();
    return;
  }
  if (name == "getCoreJob") {
    EncodableMap out;
    out["job"] =
        flutter::EncodableValue(static_cast<int64_t>(aethone::GetCoreJob()));
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
    EncodableMap out;
    out["running"] = flutter::EncodableValue(false);
    out["port"] = flutter::EncodableValue();
    result->Success(flutter::EncodableValue(out));
    return;
  }
  if (name == "readCoreLog") {
    const int tail = ArgInt(args, "tail", 64 * 1024);
    int64_t total = 0;
    const std::string text = aethone::ReadCoreLogTail(tail, &total);
    EncodableMap out;
    out["text"] = flutter::EncodableValue(text);
    out["totalBytes"] = flutter::EncodableValue(static_cast<int64_t>(total));
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

void RegisterEngineChannel(flutter::PluginRegistrar* registrar) {
  if (registrar == nullptr) return;
  // A static unique_ptr parks the channel for the life of the process (the
  // runner never tears it down before exit — Unregister only nulls the
  // emitting pointer).
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      parked;
  parked = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "aethone/engine",
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
