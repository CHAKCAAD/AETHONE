// tray_icon_windows.cc — see tray_icon_windows.h for the contract.
#include "tray_icon_windows.h"

#include "resource.h"

#include <cstring>

namespace aethone {
namespace {

constexpr UINT kTrayCallbackMsg = WM_APP + 101;
constexpr int kMenuShowId = 100;
constexpr int kMenuQuitId = 101;
constexpr wchar_t kSinkClass[] = L"AETHONE_TRAY_SINK";

// Persian menu labels as explicit UTF-16 code units — the runner compiles
// without /utf-8 (windows/CMakeLists.txt applies /W4 /WX but no source
// codepage flag), so raw UTF-8 literals in the source would be misread on
// any non-Persian system codepage. The escapes are codepage-proof:
//   نمایش = U+0646 U+0645 U+0627 U+06CC U+0634   (show)
//   خروج  = U+062E U+0631 U+0648 U+062C          (exit)
constexpr wchar_t kMenuShow[] = L"\x0646\x0645\x0627\x06CC\x0634 AETHONE";
constexpr wchar_t kMenuQuit[] = L"\x062E\x0631\x0648\x062C";
constexpr wchar_t kTrayTip[] = L"AETHONE";

}  // namespace

TrayController* TrayController::Instance() {
  static TrayController instance;
  return &instance;
}

bool TrayController::EnsureAdded(HWND main) {
  main_ = main;
  if (sink_ == nullptr) {
    const HINSTANCE instance = GetModuleHandle(nullptr);
    taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
    WNDCLASS wc{};
    wc.lpfnWndProc = &TrayController::WndProc;
    wc.hInstance = instance;
    wc.lpszClassName = kSinkClass;
    if (RegisterClassW(&wc) == 0) return false;
    sink_ = CreateWindowExW(0, kSinkClass, L"", WS_POPUP, 0, 0, 0, 0,
                            nullptr, nullptr, instance, this);
    if (sink_ == nullptr) return false;
  }
  if (icon_added_) return true;

  ZeroMemory(&nid_, sizeof(nid_));
  nid_.cbSize = sizeof(nid_);
  nid_.hWnd = sink_;
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = kTrayCallbackMsg;
  nid_.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_TRAY_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));
  if (nid_.hIcon == nullptr) return false;
  wcscpy_s(nid_.szTip, sizeof(nid_.szTip) / sizeof(nid_.szTip[0]), kTrayTip);

  if (!Shell_NotifyIconW(NIM_ADD, &nid_)) {
    DestroyIcon(nid_.hIcon);
    nid_.hIcon = nullptr;
    return false;
  }
  icon_added_ = true;
  return true;
}

void TrayController::Remove() {
  if (!icon_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &nid_);
  if (nid_.hIcon != nullptr) {
    DestroyIcon(nid_.hIcon);
    nid_.hIcon = nullptr;
  }
  icon_added_ = false;
}

void TrayController::RestoreMain() {
  if (main_ == nullptr) return;
  ShowWindow(main_, SW_RESTORE);
  SetForegroundWindow(main_);
}

void TrayController::ShowMenu() {
  POINT pt;
  GetCursorPos(&pt);
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kMenuShowId, kMenuShow);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuitId, kMenuQuit);
  // The classic tray quirk: without foreground + the trailing WM_NULL the
  // menu can refuse to dismiss on the first outside click.
  SetForegroundWindow(sink_);
  const int picked = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                    pt.x, pt.y, 0, sink_, nullptr);
  PostMessageW(sink_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (picked == kMenuShowId) {
    RestoreMain();
  } else if (picked == kMenuQuitId) {
    QuitFromTray();
  }
}

bool TrayController::HideToTray(HWND main) {
  if (!EnsureAdded(main)) {
    return false;  // the caller keeps the default close path
  }
  ShowWindow(main_, SW_HIDE);
  return true;
}

void TrayController::QuitFromTray() {
  Remove();
  if (main_ != nullptr) {
    DestroyWindow(main_);
  }
}

void TrayController::HandleSinkMessage(HWND, UINT message, WPARAM,
                                       LPARAM lparam) {
  if (message == kTrayCallbackMsg) {
    const UINT mouse = static_cast<UINT>(lparam);
    if (mouse == WM_LBUTTONUP || mouse == WM_LBUTTONDBLCLK) {
      RestoreMain();
    } else if (mouse == WM_RBUTTONUP || mouse == WM_CONTEXTMENU) {
      ShowMenu();
    }
    return;
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    // Explorer restarted: put the icon back (the owner's mark stays in the
    // tray across shell crashes).
    if (icon_added_) {
      Shell_NotifyIconW(NIM_ADD, &nid_);
    }
  }
}

LRESULT CALLBACK TrayController::WndProc(HWND window, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return DefWindowProc(window, message, wparam, lparam);
  }
  TrayController* that =
      reinterpret_cast<TrayController*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (that != nullptr) {
    that->HandleSinkMessage(window, message, wparam, lparam);
    return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

}  // namespace aethone
