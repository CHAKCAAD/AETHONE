// tray_icon_windows.h — v4.39 close-to-tray for the Windows runner,
// v4.40 the owner's round-15 menu (show / toggle connection / quit).
//
// The owner's decree (delivered in Persian, 2026-11-07): when the user
// clicks the window's close button, the app must not quit — it shrinks
// into the system tray instead. The tunnel and every engine keep running
// in the background; the tray icon carries the owner's mark EXACTLY as
// delivered (the transparent face of design/brand/aethone-logo.svg,
// embedded as the IDI_TRAY_ICON resource). The v4.40 decree adds the menu
// the owner asked for verbatim («بستن کلی برنامه» / «نمایش اپ» / «قطع و
// وصل اتصال») and moves the CLOSE DECISION to the Dart layer: WM_CLOSE now
// asks the app (which shows the owner's ask-dialog with the remember
// checkbox) instead of hiding unconditionally. This file compiles under
// MSVC without /utf-8, so the sources here stay pure ASCII; the decree's
// own wording lives verbatim in the Linux twin (tray_controller_linux.h).
//
// Main-thread only (it owns a hidden message window driven by the same
// pump aethone.exe already runs).
#pragma once

#include <windows.h>

#include <shellapi.h>  // NOTIFYICONDATAW / Shell_NotifyIconW

namespace aethone {

// The tray-side callbacks the engine channel registers (main thread).
// toggle_connection: the «قطع و وصل اتصال» menu entry — the DART side owns
// the connection state machine, so the pick is forwarded there.
using TrayToggleConnectionCallback = void (*)();

class TrayController {
 public:
  // The process-wide instance (never null after first call).
  static TrayController* Instance();

  // Adds the tray icon and hides `main`. Returns false when the
  // notification area rejected the icon — the caller then keeps the
  // default close (destroy) semantics. Idempotent on further calls.
  bool HideToTray(HWND main);

  // Remembers the main window without hiding (the Dart layer's
  // window.hide lands here after its own ask-dialog).
  void RememberMain(HWND main) { main_ = main; }

  // The tray menu's خروج entry: removes the icon and destroys the window
  // (the app exits through the normal WM_DESTROY path).
  void QuitFromTray();

  // v4.40 — the «قطع و وصل اتصال» menu entry's sink (set by the engine
  // channel; the Dart layer decides connect vs disconnect).
  void SetToggleConnectionCallback(TrayToggleConnectionCallback cb) {
    toggle_cb_ = cb;
  }

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
  TrayToggleConnectionCallback toggle_cb_ = nullptr;
  NOTIFYICONDATAW nid_ = {};
};

}  // namespace aethone
