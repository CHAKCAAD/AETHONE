#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <stdlib.h>

#include "flutter_window.h"
#include "utils.h"

#include "desktop_shared/desktop_engine.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // v4.36 — marks this process as a REAL desktop app for the Dart layer
  // (the store's engine engagement + the adapter's honest resume). The test
  // hosts never set it, which is exactly how they keep the legacy path.
  _putenv_s("AETHONE_DESKTOP_ENGINE", "1");

  // v4.36 — the desktop boot sequence, BEFORE any engine/Dart code runs:
  // the bounded core-log capture (the installCoreLogRedirect twin; the
  // embedded Rust core logs onto fd 2). The aether cdylib preload is a
  // Windows-side bundle EXISTENCE check — LoadLibrary finds aether.dll in
  // the exe dir natively when the Dart side opens it.
  aethone::InstallCoreLogCapture();
  const std::string preload_error = aethone::PreloadAetherLibrary();
  if (!preload_error.empty()) {
    OutputDebugStringA(("aethone: " + preload_error + "\n").c_str());
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // v4.36 — the design package's own phone frame (402x874, the
  // reference-screen CSS "iPhone 17 - 22"): the desktop window opens at the
  // same size the Android app renders, so the UI is pixel-identical.
  // Win32Window::Create scales logical to physical px per-monitor.
  Win32Window::Size size(402, 874);
  if (!window.Create(L"AETHONE", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
