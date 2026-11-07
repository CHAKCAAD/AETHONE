// io.h — the signature-faithful stub for the v4.40 desktop_engine.cpp
// WINDOWS-half syntax leg (see scripts/syntax_check_linux_runner.sh).
// Mirrors the MSVC CRT low-io surface the log capture uses.
#pragma once

#include <cstdio>  // FILE

#define _O_BINARY 0x8000

int _pipe(int* fds, unsigned int psize, int textmode);
int _dup2(int fd1, int fd2);
int _close(int fd);
int _fseeki64(FILE* stream, long long offset, int origin);
long long _ftelli64(FILE* stream);
