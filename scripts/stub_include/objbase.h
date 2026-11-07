// objbase.h — the signature-faithful stub for the v4.40 desktop_engine.cpp
// WINDOWS-half syntax leg (see scripts/syntax_check_linux_runner.sh).
#pragma once

#include <windows.h>

typedef enum tagCOINIT {
  COINIT_APARTMENTTHREADED = 0x2,
} COINIT;

HRESULT CoInitializeEx(LPVOID pvReserved, DWORD dwCoInit);
void CoUninitialize(void);
