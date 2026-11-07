#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <tlhelp32.h>  // v4.40 — the crash log's module walk

#include <cstdio>
#include <cstring>
#include <string>

#include <cstdlib>

#include "flutter_window.h"
#include "utils.h"

#include "desktop_shared/desktop_engine.h"

namespace {
// v4.39 — a kill-on-close job object over the whole process: when
// aethone.exe exits (any path — quit, crash, task-kill), every child core
// it spawned (psiphon.exe / lyrebird.exe) dies with it. The owner's device
// test showed the engines lingering after earlier sessions; this round's
// aether build patch hides their windows while running, and the job object
// reaps them at exit. Best effort: a host that already nests us in a job
// that forbids it just skips the guard.
HANDLE g_engine_job = nullptr;

// v4.40 — THE CRASH LOG. The owner's r86 device reports — "the app fully
// closes" on a VPN connect, the Windows illegal-instruction dialog on a
// proxy connect — left NO evidence behind (Windows shows an address like
// 0x00007ffe097190a0 that cannot be mapped to a module without a dump).
// This filter writes the one fact that matters into
// <filesDir>/logs/crash-log.txt BEFORE the process dies: the exception code,
// the faulting address, and the MODULE NAME + offset (the walk over the
// loaded modules via Toolhelp). The FMA fix in this round explains the
// engine-child crashes; this log names whatever remains, on the very next
// device test, without asking the owner for a dump.
//
// Best-effort by design: async-signal-safety is not guaranteed (file I/O in
// a crash filter) — the alternative (no evidence) is strictly worse. The
// return keeps the default WER chain intact: the user still sees the
// system's crash dialog exactly as before.
std::string ModuleAt(uintptr_t address, uintptr_t* offset_out) {
  *offset_out = 0;
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
  if (snap == INVALID_HANDLE_VALUE) return "<snapshot failed>";
  std::string found = "<unknown module>";
  MODULEENTRY32W me{};
  me.dwSize = sizeof(me);
  if (Module32FirstW(snap, &me)) {
    do {
      const uintptr_t base = reinterpret_cast<uintptr_t>(me.modBaseAddr);
      if (address >= base && address < base + me.modBaseSize) {
        char name[64];
        size_t n = 0;
        for (size_t i = 0; me.szModule[i] != L'\0' && i + 1 < sizeof(name); ++i) {
          const wchar_t c = me.szModule[i];
          name[n++] = (c > 0 && c < 128) ? static_cast<char>(c) : '?';
        }
        name[n] = '\0';
        found = name;
        *offset_out = address - base;
        break;
      }
    } while (Module32NextW(snap, &me));
  }
  CloseHandle(snap);
  return found;
}

LONG WINAPI CrashLogFilter(EXCEPTION_POINTERS* ep) {
  if (ep != nullptr && ep->ExceptionRecord != nullptr) {
    const EXCEPTION_RECORD* rec = ep->ExceptionRecord;
    const uintptr_t addr = reinterpret_cast<uintptr_t>(rec->ExceptionAddress);
    uintptr_t off = 0;
    const std::string module = ModuleAt(addr, &off);
    FILE* f = nullptr;
    const std::string log = aethone::Paths().filesDir + "/logs/crash-log.txt";
    fopen_s(&f, log.c_str(), "a");
    if (f != nullptr) {
      SYSTEMTIME st{};
      GetLocalTime(&st);
      fprintf(f,
              "[%04u-%02u-%02u %02u:%02u:%02u] code=0x%08lX address=0x%016zx "
              "module=%s+0x%zx flags=0x%08lx params=%lu\n",
              st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
              rec->ExceptionCode, (size_t)addr, module.c_str(), (size_t)off,
              rec->ExceptionFlags, (unsigned long)rec->NumberParameters);
      fclose(f);
    }
  }
  return EXCEPTION_CONTINUE_SEARCH;  // WER still shows its own dialog
}
}  // namespace

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

  // v4.39 — the engine-reaping job object (see the comment above the
  // g_engine_job definition).
  {
    HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
    if (job != nullptr) {
      JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
      info.BasicLimitInformation.LimitFlags =
          JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      if (::SetInformationJobObject(
              job, JobObjectExtendedLimitInformation, &info, sizeof(info)) &&
          ::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
        g_engine_job = job;  // held open for the process lifetime
      } else {
        ::CloseHandle(job);
      }
    }
  }

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
  // v4.40 — the crash log filter (see CrashLogFilter above) and the
  // system-proxy hygiene (a previous session that died with the OS proxy
  // set gets its state restored right here, before the UI comes up).
  ::SetUnhandledExceptionFilter(&CrashLogFilter);
  {
    const std::string proxy_err = aethone::SystemProxyHygiene();
    if (!proxy_err.empty()) {
      OutputDebugStringA(("aethone: system-proxy hygiene: " + proxy_err +
                          "\n")
                             .c_str());
    }
  }
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
  // Win32Window::Create scales logical to physical px per-monitor and
  // (v4.40) clamps to the monitor's work area — small screens get the whole
  // window on-screen, centred.
  Win32Window::Size size(402, 874);
  if (!window.Create(L"AETHONE", origin, size)) {
    return EXIT_FAILURE;
  }
  // Quit stays bound to the destroy path: window.quit (the ask-dialog or the
  // tray menu's Exit) lands in TrayController::QuitFromTray → DestroyWindow
  // → WM_DESTROY → PostQuitMessage. WM_CLOSE itself never reaches here
  // anymore — FlutterWindow routes it into Dart (v4.40).
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
