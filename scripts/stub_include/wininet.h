// wininet.h — the signature-faithful stub for the v4.40 local syntax gate
// (the desktop_engine.cpp Windows-half leg; see scripts/
// syntax_check_linux_runner.sh). MSVC is unavailable in this sandbox; this
// mirrors exactly the surface desktop_engine.cpp's system-proxy companion
// touches, declaration-for-declaration as the Windows SDK pins them.
#pragma once

#include <windows.h>

typedef void* HINTERNET;

#define INTERNET_OPTION_SETTINGS_CHANGED 39
#define INTERNET_OPTION_REFRESH 37

extern "C" {
BOOL InternetSetOptionW(HINTERNET hInternet, DWORD dwOption, LPVOID lpBuffer,
                        DWORD dwBufferLength);
}
