// engine_channel_linux.cc — the `aethone/engine` MethodChannel for the GTK
// runner (v4.36 desktop round). One thin adapter over desktop_shared: the
// exact surface MainActivity.kt hosts on Android, method for method, so
// lib/connection/platform_engine_adapter.dart runs unchanged.
//
// Registered from my_application.cc right after fl_register_plugins() — the
// same ordering as Android's configureFlutterEngine.
#include <flutter_linux/flutter_linux.h>

#include <cstdio>
#include <string>

#include "desktop_shared/desktop_engine.h"
#include "engine_channel_linux.h"

namespace {

FlMethodChannel* g_channel = nullptr;  // strong ref, cleared in Unregister

// ---- FlValue map helpers (GLib refcounting: values are owned by us) ----

int ArgInt(FlValue* args, const char* key, int fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_INT) return fallback;
  return static_cast<int>(fl_value_get_int(v));
}

bool ArgBool(FlValue* args, const char* key, bool fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_BOOL) return fallback;
  return fl_value_get_bool(v);
}

// Emits one tunnel event (the EngineBridge.emit twin). Everything runs on
// the GTK main thread — the same single-thread discipline as Android.
void Emit(const char* event, int port, const char* reason, int session) {
  if (g_channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "event", fl_value_new_string(event));
  fl_value_set_string_take(args, "port", fl_value_new_int(port));
  if (reason != nullptr) {
    fl_value_set_string_take(args, "reason", fl_value_new_string(reason));
  }
  fl_value_set_string_take(args, "session", fl_value_new_int(session));
  fl_method_channel_invoke_method(g_channel, "onTunnelEvent", args, nullptr,
                                  nullptr, nullptr);
}

// fl_method_call_respond consumes the response reference (the flutter_linux
// example pattern): pass the fresh object, never a second owner.
void RespondSuccess(FlMethodCall* call, FlValue* result) {
  GError* error = nullptr;
  fl_method_call_respond(
      call, FL_METHOD_RESPONSE(fl_method_success_response_new(result)),
      &error);
  if (error != nullptr) {
    g_warning("aethone/engine respond failed: %s", error->message);
    g_error_free(error);
  }
}

void RespondError(FlMethodCall* call, const char* code, const char* message) {
  GError* error = nullptr;
  fl_method_call_respond(
      call, FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr)),
      &error);
  if (error != nullptr) {
    g_warning("aethone/engine respond failed: %s", error->message);
    g_error_free(error);
  }
}

void HandleMethodCall(FlMethodChannel* channel, FlMethodCall* call,
                      gpointer user_data) {
  (void)channel;
  (void)user_data;
  const char* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (g_strcmp0(name, "paths") == 0) {
    const aethone::DesktopPaths& p = aethone::Paths();
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "filesDir",
                              fl_value_new_string(p.filesDir.c_str()));
    // The Dart layer builds `<nativeLibraryDir>/liblyrebird.so` when the
    // explicit paths are absent — keep pointing it somewhere honest (the
    // bundle's lib dir) even though the desktop always answers the
    // explicit fields below.
    fl_value_set_string_take(result, "nativeLibraryDir",
                              fl_value_new_string((p.exeDir + "/lib").c_str()));
    fl_value_set_string_take(result, "lyrebirdPath",
                             fl_value_new_string(p.lyrebirdBin.c_str()));
    fl_value_set_string_take(result, "psiphonPath",
                             fl_value_new_string(p.psiphonBin.c_str()));
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "prepareVpn") == 0) {
    // Desktop: no OS consent dialog — privilege is enforced at TUN open and
    // surfaces as the honest zeptun error when elevated rights are missing.
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "needsPermission", fl_value_new_bool(false));
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "startVpn") == 0) {
    const int port = ArgInt(args, "port", 1819);
    const int session = ArgInt(args, "session", 0);
    const bool tcpOnly = ArgBool(args, "tcpOnly", false);
    const aethone::TunnelStartResult res =
        aethone::StartTunnel(port, session, tcpOnly);
    switch (res.kind) {
      case aethone::TunnelStartKind::kOk:
        RespondSuccess(call, nullptr);
        Emit("up", port, nullptr, session);
        return;
      case aethone::TunnelStartKind::kStaleSession:
        // The straggler gate: a start superseded by a newer stop refuses to
        // establish (the Kotlin twin) — reported as a down event, never an
        // up. The Dart walk drops it through its session tag anyway.
        RespondSuccess(call, nullptr);
        Emit("down", 0, res.reason.c_str(), session);
        return;
      case aethone::TunnelStartKind::kError:
        RespondError(call, "tunnelStartFailed", res.reason.c_str());
        return;
    }
    return;
  }
  if (g_strcmp0(name, "stopVpn") == 0) {
    const int session = aethone::StopTunnel();
    RespondSuccess(call, nullptr);
    Emit("down", 0, "destroy", session);
    return;
  }
  if (g_strcmp0(name, "vpnStatus") == 0) {
    const aethone::TunnelCounters c = aethone::ReadTunnelCounters();
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "running", fl_value_new_bool(c.running));
    fl_value_set_string_take(
        result, "port",
        c.running ? fl_value_new_int(c.port) : fl_value_new_null());
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "zeptunCounters") == 0) {
    const aethone::TunnelCounters c = aethone::ReadTunnelCounters();
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "rxBytes", fl_value_new_int(c.rxBytes));
    fl_value_set_string_take(result, "txBytes", fl_value_new_int(c.txBytes));
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "setCoreJob") == 0) {
    aethone::SetCoreJob(ArgInt(args, "job", 0));
    RespondSuccess(call, nullptr);
    return;
  }
  if (g_strcmp0(name, "getCoreJob") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "job",
                              fl_value_new_int(aethone::GetCoreJob()));
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "clearCoreJob") == 0) {
    aethone::ClearCoreJob();
    RespondSuccess(call, nullptr);
    return;
  }
  if (g_strcmp0(name, "startCoreHold") == 0) {
    // Desktop: the Flutter window IS the process — while it stays open the
    // in-process core keeps serving (the Android CoreHoldService exists only
    // because Android may kill the backgrounded process). Honest no-op.
    RespondSuccess(call, nullptr);
    return;
  }
  if (g_strcmp0(name, "stopCoreHold") == 0) {
    RespondSuccess(call, nullptr);
    return;
  }
  if (g_strcmp0(name, "coreHoldStatus") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "running", fl_value_new_bool(false));
    fl_value_set_string_take(result, "port", fl_value_new_null());
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "readCoreLog") == 0) {
    const int tail = ArgInt(args, "tail", 64 * 1024);
    int64_t total = 0;
    const std::string text = aethone::ReadCoreLogTail(tail, &total);
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "text", fl_value_new_string(text.c_str()));
    fl_value_set_string_take(result, "totalBytes", fl_value_new_int(total));
    RespondSuccess(call, result);
    return;
  }
  if (g_strcmp0(name, "clearCoreLog") == 0) {
    aethone::ClearCoreLog();
    RespondSuccess(call, nullptr);
    return;
  }
  fl_method_call_respond(
      call, FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()),
      nullptr);
}

}  // namespace

namespace aethone {

void RegisterEngineChannel(FlEngine* engine) {
  g_return_if_fail(engine != nullptr);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(messenger, "aethone/engine",
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, HandleMethodCall,
                                            nullptr, nullptr);
}

void UnregisterEngineChannel() {
  if (g_channel != nullptr) {
    g_clear_object(&g_channel);
  }
}

}  // namespace aethone
