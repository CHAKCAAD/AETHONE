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
#include <ctime>

typedef int errno_t;
typedef unsigned long DWORD;
typedef long LONG;
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

// ---- v4.40: the registry / time / file surface (the desktop_engine.cpp
// WINDOWS-half leg — the system-proxy companion + the auto-start). The
// signature-faithful mirror of the SDK pins, so g++ -fsyntax-only catches
// the argument mistakes before they burn a CI cycle (exactly what run 88's
// Windows leg died on: WideToUtf8's 2-arg form).
typedef struct HKEY__* HKEY;
typedef HKEY* PHKEY;
typedef DWORD REGSAM;
typedef unsigned char BYTE;
typedef BYTE* LPBYTE;
typedef const BYTE* LPCBYTE;
typedef char* LPSTR;

typedef struct _SYSTEMTIME {
  WORD wYear;
  WORD wMonth;
  WORD wDayOfWeek;
  WORD wDay;
  WORD wHour;
  WORD wMinute;
  WORD wSecond;
  WORD wMilliseconds;
} SYSTEMTIME;
typedef SYSTEMTIME* LPSYSTEMTIME;

#define HKEY_CURRENT_USER ((HKEY)0x80000001)
#define KEY_READ 0x20019
#define KEY_WRITE 0x20006
#define ERROR_SUCCESS 0L
#define ERROR_FILE_NOT_FOUND 2L
#define REG_SZ 1
#define REG_EXPAND_SZ 2
#define REG_DWORD 4

LONG RegOpenKeyExW(HKEY hKey, LPCWSTR lpSubKey, DWORD ulOptions, REGSAM samDesired, PHKEY phkResult);
LONG RegQueryValueExW(HKEY hKey, LPCWSTR lpValueName, LPVOID lpReserved, DWORD* lpType, LPBYTE lpData, DWORD* lpcbData);
LONG RegSetValueExW(HKEY hKey, LPCWSTR lpValueName, DWORD Reserved, DWORD dwType, const BYTE* lpData, DWORD cbData);
LONG RegDeleteValueW(HKEY hKey, LPCWSTR lpValueName);
LONG RegCloseKey(HKEY hKey);

void GetLocalTime(LPSYSTEMTIME lpSystemTime);
DWORD GetModuleFileNameA(HMODULE hModule, LPSTR lpFilename, DWORD nSize);
DWORD GetModuleFileNameW(HMODULE hModule, LPWSTR lpFilename, DWORD nSize);
BOOL CloseHandle(HANDLE hObject);
DWORD GetCurrentProcessId(void);
HANDLE GetCurrentProcess(void);

// ---- the v4.39 UTF-8/W boundary + library-loading surface ----
typedef LONG HRESULT;
#define CP_UTF8 65001
int MultiByteToWideChar(UINT CodePage, DWORD dwFlags, const char* lpMultiByteStr,
                        int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar);
int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, const wchar_t* lpWideCharStr,
                        int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte,
                        const char* lpDefaultChar, BOOL* lpUsedDefaultChar);
DWORD GetLastError(void);
#define LOAD_LIBRARY_SEARCH_APPLICATION_DIR 0x00000800
#define LOAD_LIBRARY_SEARCH_SYSTEM32 0x00000800
#define LOAD_WITH_ALTERED_SEARCH_PATH 0x00000008
HMODULE LoadLibraryExW(LPCWSTR lpLibFileName, HANDLE hFile, DWORD dwFlags);
BOOL FreeLibrary(HMODULE hLibModule);
typedef void (*FARPROC)(void);  // placeholder under g++ (never linked)
FARPROC GetProcAddress(HMODULE hModule, const char* lpProcName);
DWORD GetFileAttributesW(LPCWSTR lpFileName);
FILE* _wfopen(const wchar_t* filename, const wchar_t* mode);
int _wremove(const wchar_t* path);
int _wrename(const wchar_t* oldname, const wchar_t* newname);
errno_t fopen_s(FILE** pFile, const char* filename, const char* mode);
wchar_t* _wgetcwd(wchar_t* buffer, int maxlen);
int _read(int fd, void* buffer, unsigned int count);
errno_t localtime_s(struct tm* const tmDest, time_t const* const source);
#define SUCCEEDED(hr) (((HRESULT)(hr)) >= 0)
#define FILE_ATTRIBUTE_DIRECTORY 0x00000010
BOOL SetUnhandledExceptionFilter(void* lpTopLevelExceptionFilter);

#define ZeroMemory(p, n) memset((p), 0, (n))
#define DefWindowProc DefWindowProcW
#define SetWindowLongPtr SetWindowLongPtrW
#define GetWindowLongPtr GetWindowLongPtrW
#define GetModuleHandle GetModuleHandleW
#define MAKEINTRESOURCEW(i) ((LPCWSTR)(uintptr_t)(i))
