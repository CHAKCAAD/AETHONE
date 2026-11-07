// tray_icon_windows.h — v4.39 close-to-tray for the Windows runner.
//
// The owner's decree (delivered in Persian, 2026-11-07): when the user
// clicks the window's close button, the app must not quit — it shrinks
// into the system tray instead. The tunnel and every engine keep running
// in the background; the tray icon carries the owner's mark EXACTLY as
// delivered (the transparent face of design/brand/aethone-logo.svg,
// embedded as the IDI_TRAY_ICON resource), and the tray menu offers
// Show (Persian) / Exit (Persian). This file compiles under MSVC without
// /utf-8, so the sources here stay pure ASCII; the decree's own wording
// lives verbatim in the Linux twin (tray_controller_linux.h).
//
// Main-thread only (it owns a hidden message window driven by the same
// pump aethone.exe already runs).
#pragma once

#include <windows.h>

#include <shellapi.h>  // NOTIFYICONDATAW / Shell_NotifyIconW

namespace aethone {

class TrayController {
 public:
  // The process-wide instance (never null after first call).
  static TrayController* Instance();

  // Adds the tray icon and hides `main`. Returns false when the
  // notification area rejected the icon — the caller then keeps the
  // default close (destroy) semantics. Idempotent on further calls.
  bool HideToTray(HWND main);

  // The tray menu's خروج entry: removes the icon and destroys the window
  // (the app exits through the normal WM_DESTROY path).
  void QuitFromTray();

  bool added() const { return icon_added_; }

 private:
  TrayController() = default;

  bool EnsureAdded(HWND main);
  void Remove();
  void RestoreMain();
  void ShowMenu();
  void HandleSinkMessage(HWND sink, UINT message, WPARAM wparam,
                         LPARAM lparam);

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);

  HWND main_ = nullptr;        // the app window we hide/restore
  HWND sink_ = nullptr;        // the hidden callback window
  UINT taskbar_created_ = 0;   // RegisterWindowMessage("TaskbarCreated")
  bool icon_added_ = false;
  NOTIFYICONDATAW nid_ = {};
};

}  // namespace aethone
