#include <cstdlib>

#include "my_application.h"

#include "desktop_shared/desktop_engine.h"

int main(int argc, char** argv) {
  // v4.39 — THE owner's Linux model, before anything else in this process
  // (no capture pipe, no GTK, no engine state — a clean exec): relaunch the
  // whole app as root through ONE polkit prompt, so the TUN bring-up AND
  // every engine the core spawns in the background run privileged with no
  // further prompts («از ابتدا برنامه باید با دسترسی sudo اجرا بشه»).
  // When the elevated child ran to completion this process is done; on
  // decline / headless CI / no-polkit we fall through and run right here
  // as the unprivileged app (the v4.37 helper path stays the fallback).
  int elevated_exit = 0;
  if (aethone::ElevateAtStartup(&elevated_exit)) {
    return elevated_exit;
  }

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
  // v4.39 — the root instance's idempotent system integration (the menu
  // entry + the hicolor icon); its outcome lands in the captured core log.
  aethone::EnsureDesktopIntegration();

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
