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
#include <thread>

#include "desktop_shared/desktop_engine.h"
#include "engine_channel_linux.h"
#include "tray_controller_linux.h"

namespace {

FlMethodChannel* g_channel = nullptr;  // strong ref, cleared in Unregister

// forward declarations (definitions below, after the FlValue helpers)
void RespondSuccess(FlMethodCall* call, FlValue* result);
void RespondError(FlMethodCall* call, const char* code, const char* message);

// v4.37 — everything the tunnel worker threads need to talk back to the GTK
// main loop. g_idle_add is safe to call from any thread; the Flutter/GTK
// calls themselves are NOT, so they all happen inside the idle callbacks.
struct IdleBox {
  std::string event;   // "up" | "down"
  std::string reason;  // down reasons, verbatim from the engine layer
  int port = 0;
  int session = 0;
};

gboolean EmitIdle(gpointer data) {
  IdleBox* box = static_cast<IdleBox*>(data);
  if (g_channel != nullptr && box != nullptr) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "event", fl_value_new_string(box->event.c_str()));
    fl_value_set_string_take(args, "port", fl_value_new_int(box->port));
    if (!box->reason.empty()) {
      fl_value_set_string_take(args, "reason", fl_value_new_string(box->reason.c_str()));
    }
    fl_value_set_string_take(args, "session", fl_value_new_int(box->session));
    fl_method_channel_invoke_method(g_channel, "onTunnelEvent", args, nullptr,
                                    nullptr, nullptr);
  }
  delete box;
  return FALSE;  // one-shot
}

// The engine layer's sink — invoked on the HELPER WORKER thread. Named
// OnTunnelEvent (NOT TunnelEventSink): that name is the callback TYPE alias
// in desktop_engine.h's namespace aethone, and inside namespace aethone the
// alias hides this file-scope function — passing it unqualified is a hard
// compile error (run 42282415458, clang: "unexpected type name").
void OnTunnelEvent(void*, const aethone::TunnelEvent& event) {
  IdleBox* box = new IdleBox();
  box->event = event.up ? "up" : "down";
  box->reason = event.reason;
  box->port = event.port;
  box->session = event.session;
  g_idle_add(EmitIdle, box);
}

// The async verifyTunnelPath response (worker thread → main loop).
struct VerifyBox {
  FlMethodCall* call;  // reffed for the trip
  bool attempted;
  bool verified;
  int64_t elapsedMs;
  std::string detail;
};

gboolean VerifyRespondIdle(gpointer data) {
  VerifyBox* box = static_cast<VerifyBox*>(data);
  if (box != nullptr) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "attempted", fl_value_new_bool(box->attempted));
    fl_value_set_string_take(result, "verified", fl_value_new_bool(box->verified));
    fl_value_set_string_take(result, "elapsedMs", fl_value_new_int(box->elapsedMs));
    fl_value_set_string_take(result, "detail", fl_value_new_string(box->detail.c_str()));
    RespondSuccess(box->call, result);
    g_object_unref(box->call);
    delete box;
  }
  return FALSE;
}

void VerifyWorker(FlMethodCall* call) {
  VerifyBox* box = new VerifyBox();
  box->call = call;  // carries the ref taken by the handler
  const aethone::TunnelPathProbe probe = aethone::VerifyTunnelPath();
  box->attempted = probe.attempted;
  box->verified = probe.verified;
  box->elapsedMs = probe.elapsedMs;
  box->detail = probe.detail;
  g_idle_add(VerifyRespondIdle, box);
}

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
    // v4.38 — the psiphon family's strict-socks handshake (pipeline=false
    // + optimistic_data=false): its goptlib listener rejects pipelined
    // bytes, which killed every TCP flow of the psiphon tunnel while the
    // sequential probe passed (the round-13 addendum defect).
    const bool socksStrict = ArgBool(args, "socksStrict", false);
    // v4.37 — the Linux privilege path: as a normal user the TUN/link/route
    // setup needs CAP_NET_ADMIN, so the bring-up goes through the Polkit
    // helper (pkexec password prompt — can take MINUTES). The Android model
    // applies: accept the request, complete on the event channel. The Dart
    // walk's Linux tunnelUp budget (180 s, the permission budget) covers
    // the dialog. Root/Windows keep the synchronous path unchanged.
    if (aethone::TunnelPrivilegeViaHelper()) {
      aethone::StartTunnelAsync(port, session, tcpOnly, socksStrict);
      RespondSuccess(call, nullptr);
      return;
    }
    const aethone::TunnelStartResult res =
        aethone::StartTunnel(port, session, tcpOnly, socksStrict);
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
  if (g_strcmp0(name, "verifyTunnelPath") == 0) {
    // v4.37 — the through-tunnel data-path verification (requirement D):
    // the helper (uid 0, not excluded from the TUN) makes a REAL request
    // through the tunnel. SLOW (up to ~20 s) — never on the GTK main
    // thread; the response is marshaled back with g_idle_add.
    g_object_ref(call);
    std::thread(VerifyWorker, call).detach();
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
  // ---- v4.40: the window/tray surface (the close-to-tray ask-dialog) ----
  if (g_strcmp0(name, "window.hide") == 0) {
    if (!aethone::HideToTrayFromDart()) {
      RespondError(call, "trayUnavailable",
                   "the session has no system tray");
      return;
    }
    RespondSuccess(call, nullptr);
    return;
  }
  if (g_strcmp0(name, "window.quit") == 0) {
    aethone::QuitFromDart();  // destroy → the app ends with its last window
    RespondSuccess(call, nullptr);
    return;
  }
  // ---- v4.40: the system-proxy companion of the tunnel mode ----
  if (g_strcmp0(name, "setSystemProxy") == 0) {
    const std::string err = aethone::SetSystemProxy(ArgInt(args, "port", 0));
    if (!err.empty()) {
      RespondError(call, "systemProxyFailed", err.c_str());
    } else {
      RespondSuccess(call, nullptr);
    }
    return;
  }
  if (g_strcmp0(name, "clearSystemProxy") == 0) {
    const std::string err = aethone::ClearSystemProxy();
    if (!err.empty()) {
      RespondError(call, "systemProxyFailed", err.c_str());
    } else {
      RespondSuccess(call, nullptr);
    }
    return;
  }
  // ---- v4.40: the login auto-start (general settings) ----
  if (g_strcmp0(name, "setAutoStart") == 0) {
    const std::string err = aethone::SetAutoStart(ArgBool(args, "enabled", false));
    if (!err.empty()) {
      RespondError(call, "autoStartFailed", err.c_str());
    } else {
      RespondSuccess(call, nullptr);
    }
    return;
  }
  if (g_strcmp0(name, "autoStartStatus") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "enabled",
                             fl_value_new_bool(aethone::AutoStartIsEnabled()));
    RespondSuccess(call, result);
    return;
  }
  fl_method_call_respond(
      call, FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()),
      nullptr);
}

}  // namespace

namespace aethone {

// v4.40 — the tray controller's sink: close-request and toggle-connection
// forward into Dart on the GTK main thread (these fire from GTK signals,
// which ARE the main loop — the direct invoke is the Emit pattern without
// the worker-thread idle hop).
void TrayEventToDart(const char* event) {
  if (g_channel == nullptr) return;
  const char* method =
      g_strcmp0(event, "close_requested") == 0
          ? "onWindowCloseRequested"
          : "onTrayToggleConnection";
  fl_method_channel_invoke_method(g_channel, method, nullptr, nullptr,
                                  nullptr, nullptr);
}

void RegisterEngineChannel(FlEngine* engine) {
  g_return_if_fail(engine != nullptr);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(messenger, "aethone/engine",
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, HandleMethodCall,
                                            nullptr, nullptr);
  // v4.37 — the helper-mode tunnel completes asynchronously (the Polkit
  // dialog); its events arrive on this sink from the worker thread.
  // OnTunnelEvent (file scope), NOT the same-named type alias hidden inside
  // this namespace.
  SetTunnelEventSink(OnTunnelEvent, nullptr);
  // v4.40 — the close-to-tray ask-dialog + the tray menu's toggle entry.
  SetTrayEventSink(&TrayEventToDart);
}

void UnregisterEngineChannel() {
  if (g_channel != nullptr) {
    g_clear_object(&g_channel);
  }
}

}  // namespace aethone
