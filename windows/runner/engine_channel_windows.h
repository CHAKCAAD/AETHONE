// engine_channel_windows.h — the `aethone/engine` channel registration for
// the Win32 runner (v4.36 desktop round). See engine_channel_windows.cpp.
#pragma once

namespace flutter {
class PluginRegistrar;
}

namespace aethone {

// Call from FlutterWindow::OnCreate after RegisterPlugins(...) — the Android
// ordering (configureFlutterEngine: plugins first, then the channel).
void RegisterEngineChannel(flutter::PluginRegistrar* registrar);

// Drops the channel (window teardown).
void UnregisterEngineChannel();

}  // namespace aethone
