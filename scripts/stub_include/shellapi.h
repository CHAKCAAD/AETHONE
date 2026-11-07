// shellapi.h — the v4.39 stub include shim: the notification-area surface
// (NOTIFYICONDATAW / Shell_NotifyIconW) used by tray_icon_windows.cc, as
// the Windows SDK pins it. Only the fields the controller touches are
// mirrored; the struct is zero-initialized ({} ) by the caller.
#pragma once

#include "windows.h"  // the same gate tree's stub

#define NIF_MESSAGE 0x01
#define NIF_ICON 0x02
#define NIF_TIP 0x04
#define NIM_ADD 0x00
#define NIM_DELETE 0x02

typedef struct _NOTIFYICONDATAW {
  DWORD cbSize;
  HWND hWnd;
  UINT uID;
  UINT uFlags;
  UINT uCallbackMessage;
  HICON hIcon;
  WCHAR szTip[128];
  DWORD dwState;
  DWORD dwStateMask;
  WCHAR szInfo[256];
} NOTIFYICONDATAW;

BOOL Shell_NotifyIconW(DWORD dwMessage, NOTIFYICONDATAW* lpData);
