// tlhelp32.h — the signature-faithful stub for the v4.40 local syntax gate
// (the windows/runner/main.cpp crash-log leg; see scripts/
// syntax_check_linux_runner.sh). Mirrors exactly the Toolhelp surface the
// CrashLogFilter's module walk touches, as the Windows SDK pins it.
#pragma once

#include <windows.h>  // the shared stub

#define TH32CS_SNAPMODULE 0x00000008
#define INVALID_HANDLE_VALUE ((HANDLE)(intptr_t)-1)

typedef struct tagMODULEENTRY32W {
  DWORD dwSize;
  DWORD th32ModuleID;
  DWORD th32ProcessID;
  DWORD GlblcntUsage;
  DWORD ProccntUsage;
  BYTE* modBaseAddr;
  DWORD modBaseSize;
  HMODULE hModule;
  WCHAR szModule[255];
  WCHAR szExePath[260];
} MODULEENTRY32W;

HANDLE CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID);
BOOL Module32FirstW(HANDLE hSnapshot, LPMODULEENTRY32W lpme);
BOOL Module32NextW(HANDLE hSnapshot, LPMODULEENTRY32W lpme);
