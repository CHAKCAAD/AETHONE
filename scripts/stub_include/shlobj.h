// shlobj.h — the signature-faithful stub for the v4.40 desktop_engine.cpp
// WINDOWS-half syntax leg (see scripts/syntax_check_linux_runner.sh).
#pragma once

#include <windows.h>

#define CSIDL_APPDATA 0x001a

HRESULT SHGetFolderPathW(HWND hwndOwner, int nFolder, HANDLE hToken,
                         DWORD dwFlags, LPWSTR pszPath);
