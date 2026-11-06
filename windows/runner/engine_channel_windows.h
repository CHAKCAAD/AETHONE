// engine_channel_windows.h — the `aethone/engine` channel registration for
// the Win32 runner (v4.36 desktop round). See engine_channel_windows.cpp.
#pragma once

#include <flutter_plugin_registrar.h>  // FlutterDesktopPluginRegistrarRef (C API)

namespace aethone {

// Call from FlutterWindow::OnCreate after RegisterPlugins(...) — the Android
// ordering (configureFlutterEngine: plugins first, then the channel).
// v4.36h: takes the C-API registrar ref — what
// FlutterEngine::GetRegistrarForPlugin() returns in the 3.47 embedding
// (engine()->registrar() no longer exists there).
void RegisterEngineChannel(FlutterDesktopPluginRegistrarRef registrar);

// Drops the channel (window teardown).
void UnregisterEngineChannel();

}  // namespace aethone
