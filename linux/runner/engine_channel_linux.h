// engine_channel_linux.h — the `aethone/engine` channel registration for the
// GTK runner (v4.36 desktop round). See engine_channel_linux.cc.
#pragma once

#include <flutter_linux/flutter_linux.h>

namespace aethone {

// Call after fl_register_plugins() — the Android ordering
// (configureFlutterEngine: plugins first, then the channel).
void RegisterEngineChannel(FlEngine* engine);

// Drops the channel (window teardown).
void UnregisterEngineChannel();

}  // namespace aethone
