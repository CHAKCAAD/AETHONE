// windows.h — the signature-faithful Win32 stub for the v4.39 local syntax
// gate (scripts/syntax_check_linux_runner.sh, the tray_icon_windows.cc
// leg). MSVC is unavailable in this sandbox; this stub mirrors exactly the
// surface tray_icon_windows.{h,cc} touches, declaration-for-declaration as
// the Windows SDK pins them, so g++ -fsyntax-only catches argument
// order/count/type mistakes before they burn a CI cycle.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>

typedef unsigned long DWORD;
typedef long LONG_PTR;
typedef int BOOL;
typedef unsigned short WORD;
typedef WORD ATOM;
typedef unsigned int UINT;
typedef uintptr_t UINT_PTR;
typedef wchar_t WCHAR;
typedef const wchar_t* LPCWSTR;
typedef wchar_t* LPWSTR;
typedef void* LPVOID;
typedef void* HANDLE;
typedef struct HWND__* HWND;
typedef struct HICON__* HICON;
typedef struct HMENU__* HMENU;
typedef struct HINSTANCE__* HINSTANCE;
typedef struct HINSTANCE__* HMODULE;  // the SDK: HMODULE is the same handle type as HINSTANCE

typedef long LRESULT;
typedef uintptr_t WPARAM;
typedef intptr_t LPARAM;

#define CALLBACK
#define WINAPI
#define MAX_PATH 260
#define WM_NULL 0x0000
#define WM_APP 0x8000
#define WM_NCCREATE 0x0081
#define WM_LBUTTONUP 0x0202
#define WM_LBUTTONDBLCLK 0x0203
#define WM_RBUTTONUP 0x0205
#define WM_CONTEXTMENU 0x007B
#define WS_POPUP 0x80000000
#define SW_HIDE 0
#define SW_RESTORE 9
#define SM_CXSMICON 49
#define SM_CYSMICON 50
#define IMAGE_ICON 1
#define LR_DEFAULTCOLOR 0x0000
#define GWLP_USERDATA (-21)
#define MF_STRING 0x0000
#define MF_SEPARATOR 0x0800
#define TPM_RETURNCMD 0x0100
#define TPM_RIGHTBUTTON 0x0002
#define INVALID_FILE_ATTRIBUTES ((DWORD)-1)

// The proc type exists before WNDCLASS (which carries it as a field).
typedef LRESULT(CALLBACK* WNDPROC)(HWND, UINT, WPARAM, LPARAM);

typedef struct tagPOINT {
  long x;
  long y;
} POINT;

typedef struct tagWNDCLASS {
  UINT style;
  WNDPROC lpfnWndProc;
  int cbClsExtra;
  int cbWndExtra;
  HINSTANCE hInstance;
  HICON hIcon;
  HANDLE hCursor;
  HANDLE hbrBackground;
  LPCWSTR lpszMenuName;
  LPCWSTR lpszClassName;
} WNDCLASS;

typedef struct tagCREATESTRUCT {
  LPVOID lpCreateParams;
  HANDLE hInstance;
  HANDLE hMenu;
  HWND hwndParent;
  int cy;
  int cx;
  int y;
  int x;
  LONG_PTR style;
  LPCWSTR lpszName;
  LPCWSTR lpszClass;
} CREATESTRUCT;

LRESULT DefWindowProcW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
LONG_PTR GetWindowLongPtrW(HWND hWnd, int nIndex);
HMODULE GetModuleHandleW(LPCWSTR lpModuleName);
UINT RegisterWindowMessageW(LPCWSTR lpString);
ATOM RegisterClassW(const WNDCLASS* lpWndClass);
HWND CreateWindowExW(DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName,
                     DWORD dwStyle, int X, int Y, int nWidth, int nHeight,
                     HWND hWndParent, HMENU hMenu, HINSTANCE hInstance,
                     LPVOID lpParam);
BOOL ShowWindow(HWND hWnd, int nCmdShow);
BOOL SetForegroundWindow(HWND hWnd);
BOOL DestroyWindow(HWND hWnd);
BOOL GetCursorPos(POINT* lpPoint);
HANDLE LoadImageW(HINSTANCE hInst, LPCWSTR name, UINT type, int cx, int cy,
                  UINT fuLoad);
int GetSystemMetrics(int nIndex);
BOOL DestroyIcon(HICON hIcon);
BOOL PostMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
BOOL AppendMenuW(HMENU hMenu, UINT uFlags, UINT_PTR uIDNewItem,
                 LPCWSTR lpNewItem);
HMENU CreatePopupMenu(void);
BOOL TrackPopupMenu(HMENU hMenu, UINT uFlags, int x, int y, int nReserved,
                    HWND hWnd, const void* prcRect);
BOOL DestroyMenu(HMENU hMenu);

// MSVC-only safe CRT entry glibc lacks — body included (the syntax gate
// never links, but keep it honest).
inline int wcscpy_s(wchar_t* dest, size_t destsz, const wchar_t* src) {
  if (dest == nullptr || src == nullptr || destsz == 0) return 22;
  size_t i = 0;
  for (; src[i] != L'\0'; ++i) {
    if (i + 1 >= destsz) return 80;  // ERANGE-ish: truncation refused
    dest[i] = src[i];
  }
  dest[i] = L'\0';
  return 0;
}

#define ZeroMemory(p, n) memset((p), 0, (n))
#define DefWindowProc DefWindowProcW
#define SetWindowLongPtr SetWindowLongPtrW
#define GetWindowLongPtr GetWindowLongPtrW
#define GetModuleHandle GetModuleHandleW
#define MAKEINTRESOURCEW(i) ((LPCWSTR)(uintptr_t)(i))
