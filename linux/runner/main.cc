#include <cstdlib>

#include "my_application.h"

#include "desktop_shared/desktop_engine.h"

int main(int argc, char** argv) {
  // v4.36 — marks this process as a REAL desktop app for the Dart layer
  // (the store's engine engagement + the adapter's honest resume). The test
  // hosts never set it, which is exactly how they keep the legacy path.
  setenv("AETHONE_DESKTOP_ENGINE", "1", 1);
  // v4.36 — the desktop boot sequence, BEFORE any engine/Dart code runs:
  //   1. the bounded core-log capture (the installCoreLogRedirect twin);
  //   2. the aether cdylib preload (Linux has no exe-dir dlopen search; the
  //      Dart side's DynamicLibrary.open('libaether.so') then resolves to
  //      this already-loaded object).
  // Both are diagnostics/bootstrap only — failures are logged and the app
  // still starts; the honest engineNotWired/libraryMissing faces surface
  // through the connect walk when something is missing.
  aethone::InstallCoreLogCapture();
  const std::string preload_error = aethone::PreloadAetherLibrary();
  if (!preload_error.empty()) {
    g_warning("aethone: %s", preload_error.c_str());
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
