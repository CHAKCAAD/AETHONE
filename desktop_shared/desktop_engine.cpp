// desktop_engine.cpp — see desktop_shared/desktop_engine.h for the contract.
// Pure C++17, no Flutter headers: both runners link this once.
#include "desktop_engine.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <thread>

#ifdef _WIN32
#include <direct.h>
#include <fcntl.h>
#include <io.h>
#include <objbase.h>
#include <shlobj.h>
#include <windows.h>
#define GETCWD _getcwd
#define MKDIR(p) _mkdir(p)
#else
#include <dlfcn.h>
#include <fcntl.h>  // O_RDONLY
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#define GETCWD getcwd
#define MKDIR(p) mkdir(p, 0755)
#endif

#include <zeptun.h>  // the frozen pin's own header (native/zeptun/include)

namespace aethone {
namespace {

// ---- the zeptun shared library, loaded once per process ----
struct ZeptunApi {
  void* handle = nullptr;
  int (*create_from_toml)(const char*, size_t, Zeptun**) = nullptr;
  int (*start)(Zeptun*) = nullptr;
  int (*stop)(Zeptun*) = nullptr;
  void (*destroy)(Zeptun*) = nullptr;
  int (*stats)(Zeptun*, ZeptunStats*) = nullptr;
  const char* (*strerror_)(int) = nullptr;
};

ZeptunApi g_zeptun;
std::once_flag g_zeptun_once;
std::string g_zeptun_error;

template <typename Fn>
Fn Sym(void* lib, const char* name) {
#ifdef _WIN32
  return reinterpret_cast<Fn>(reinterpret_cast<void*>(
      GetProcAddress(reinterpret_cast<HMODULE>(lib), name)));
#else
  return reinterpret_cast<Fn>(dlsym(lib, name));
#endif
}

void LoadZeptunOnce() {
  const DesktopPaths& p = Paths();
#ifdef _WIN32
  HMODULE lib = LoadLibraryExW(  // NOLINT: wide string on Windows
      std::wstring(p.zeptunLib.begin(), p.zeptunLib.end()).c_str(),
      nullptr, LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
  if (lib == nullptr) {
    char buf[48];
    snprintf(buf, sizeof(buf), "LoadLibrary zeptun.dll failed (%lu)",
             GetLastError());
    g_zeptun_error = buf;
    return;
  }
  g_zeptun.handle = reinterpret_cast<void*>(lib);
#else
  void* lib = dlopen(p.zeptunLib.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (lib == nullptr) {
    const char* why = dlerror();
    g_zeptun_error = std::string("dlopen ") + p.zeptunLib + " failed: " +
                     (why ? why : "?");
    return;
  }
  g_zeptun.handle = lib;
#endif
  g_zeptun.create_from_toml = Sym<decltype(g_zeptun.create_from_toml)>(
      g_zeptun.handle, "zeptun_create_from_toml");
  g_zeptun.start =
      Sym<decltype(g_zeptun.start)>(g_zeptun.handle, "zeptun_start");
  g_zeptun.stop = Sym<decltype(g_zeptun.stop)>(g_zeptun.handle, "zeptun_stop");
  g_zeptun.destroy =
      Sym<decltype(g_zeptun.destroy)>(g_zeptun.handle, "zeptun_destroy");
  g_zeptun.stats =
      Sym<decltype(g_zeptun.stats)>(g_zeptun.handle, "zeptun_stats");
  g_zeptun.strerror_ =
      Sym<decltype(g_zeptun.strerror_)>(g_zeptun.handle, "zeptun_strerror");
  if (!g_zeptun.create_from_toml || !g_zeptun.start || !g_zeptun.stop ||
      !g_zeptun.destroy || !g_zeptun.stats || !g_zeptun.strerror_) {
    g_zeptun_error = "zeptun shared library is missing required symbols";
    g_zeptun = ZeptunApi{};  // refuse a half-loaded engine
  }
}

// ---- the live tunnel state (all guarded by one mutex) ----
struct TunnelState {
  Zeptun* engine = nullptr;
  bool up = false;
  int port = 0;
  bool tcpOnly = false;
  int session = 0;
  int liveSession = 0;
  int stopGeneration = 0;
};
std::mutex g_tunnel_mutex;
TunnelState g_tunnel;

int64_t g_core_job = 0;  // 0 = none (see header)
std::mutex g_core_job_mutex;

// ---- the core log capture state ----
constexpr int64_t kLogMaxBytes = 1024 * 1024;  // the Kotlin budget
std::string g_log_dir;    // <filesDir>/logs
std::string g_log_path;   // .../core-log.txt
std::string g_log_prev;   // .../core-log.1.txt
std::mutex g_log_clear_mutex;
bool g_log_clear_requested = false;
bool g_log_installed = false;

std::string DirName(const std::string& path) {
  const size_t slash = path.find_last_of("/\\");
  if (slash == std::string::npos) return ".";
  if (slash == 0) return "/";
  return path.substr(0, slash);
}

bool PathExists(const std::string& p) {
#ifdef _WIN32
  return GetFileAttributesA(p.c_str()) != INVALID_FILE_ATTRIBUTES;
#else
  struct stat st {};
  return stat(p.c_str(), &st) == 0;
#endif
}

void MkDirAll(const std::string& path) {
  std::string cur;
  size_t i = 0;
  if (!path.empty() && (path[0] == '/' || path[0] == '\\')) {
    cur = path[0];
    i = 1;
  }
  while (i < path.size()) {
    const size_t next = path.find_first_of("/\\", i);
    const std::string seg =
        path.substr(i, next == std::string::npos ? std::string::npos : next - i);
    if (!seg.empty()) {
      if (cur.empty() && path[0] != '/' && path[0] != '\\') {
        cur = seg;  // relative / windows drive-relative
      } else {
        cur += (cur.empty() || cur.back() == '/' || cur.back() == '\\')
                   ? ""
                   : "/";
        cur += seg;
      }
      if (!PathExists(cur)) MKDIR(cur.c_str());
    }
    if (next == std::string::npos) break;
    i = next + 1;
  }
}

std::string ExePath() {
#ifdef _WIN32
  char buf[MAX_PATH];
  const DWORD n = GetModuleFileNameA(nullptr, buf, MAX_PATH);
  return n > 0 ? std::string(buf, n) : std::string("aethone.exe");
#else
  char buf[4096];
  const ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n <= 0) return std::string();
  buf[n] = 0;
  return std::string(buf, n);
#endif
}

std::string HomeDataDir() {
#ifdef _WIN32
  char roaming[MAX_PATH];
  if (SUCCEEDED(
          SHGetFolderPathA(nullptr, CSIDL_APPDATA, nullptr, 0, roaming))) {
    return std::string(roaming) + "\\aethone";
  }
  char buf[MAX_PATH];
  if (GETCWD(buf, sizeof(buf))) return std::string(buf) + "\\aethone";
  return "aethone";
#else
  const char* xdg = getenv("XDG_DATA_HOME");
  if (xdg && *xdg) return std::string(xdg) + "/aethone";
  const char* home = getenv("HOME");
  if (home && *home) return std::string(home) + "/.local/share/aethone";
  char buf[4096];
  if (GETCWD(buf, sizeof(buf))) return std::string(buf) + "/aethone";
  return "aethone";
#endif
}

#ifdef _WIN32
// The Cloudflare WARP pools aether itself scans (aether/src/prober.rs at the
// frozen pin, MASQUE_CIDRS_V4 + MASQUE_DOH + the API fronts from consts.rs).
// Windows only: excluded from the tunnel so the WARP-leg dials keep the
// physical path (the `-only` families are refused earlier, on the Dart side).
const char* kWarpExcludeWindows[] = {
    "1.1.1.1/32",        "1.0.0.1/32",        "162.159.36.0/24",
    "162.159.46.0/24",   "162.159.137.0/24",  "162.159.192.0/24",
    "162.159.193.0/24",  "162.159.195.0/24",  "162.159.196.0/24",
    "162.159.197.0/24",  "162.159.198.0/24",  "162.159.199.0/24",
    "162.159.204.0/24",  "172.65.251.0/24",   "188.114.96.0/24",
    "188.114.97.0/24",   "188.114.98.0/24",   "188.114.99.0/24",
    "104.18.0.0/24",     "104.24.4.0/24",
};
#endif  // _WIN32

std::string BuildZeptunToml(int port, bool tcpOnly) {
  std::string doc;
  doc.reserve(900);
  doc += "preset = \"desktop\"\n";
  doc += "\n[tun]\n";
  doc += "name = \"aethone0\"\n";
  doc += "address = [\"172.19.0.1/30\"]\n";
#ifdef _WIN32
  doc += "guid = \"{6B9C1A4E-8F2D-4C37-9E61-2D0A5F3B7E88}\"\n";
#endif
  doc += "\n[handler]\n";
  doc += "kind = \"socks5\"\n";
  doc += "\n[handler.socks5]\n";
  doc += "server = \"127.0.0.1:";
  doc += std::to_string(port);
  doc += "\"\n";
  // v4.31b (the masquerading-TOML lesson): the VALUE is the document schema's
  // bool `false`, never the enum tag string "disabled". Only emitted for
  // TCP-only modes, exactly like the Kotlin builder.
  if (tcpOnly) doc += "udp = false\n";
  doc += "\n[dns]\n";
  doc += "fake_ip = true\n";
  doc += "\n[route]\n";
  doc += "auto_route = true\n";
#ifdef _WIN32
  doc += "exclude = [";
  for (size_t i = 0; i < sizeof(kWarpExcludeWindows) / sizeof(kWarpExcludeWindows[0]);
       ++i) {
    if (i) doc += ", ";
    doc += "\"";
    doc += kWarpExcludeWindows[i];
    doc += "\"";
  }
  doc += "]\n";
#else
  doc += "exclude_uid = [\"";
  doc += std::to_string(static_cast<int>(getuid()));
  doc += "\"]\n";
#endif
  return doc;
}

// The reader thread of the capture (single writer — the Kotlin discipline).
void LogReaderLoop(int read_fd) {
  std::string current = g_log_path;
  std::string prev = g_log_prev;
  FILE* out = nullptr;
  int64_t written = 0;
  auto reopen = [&](bool truncate) {
    if (out) fclose(out);
    out = nullptr;
    if (!truncate) {
      FILE* probe = fopen(current.c_str(), "rb");
      if (probe) {
#ifdef _WIN32
        _fseeki64(probe, 0, SEEK_END);
        const int64_t len = _ftelli64(probe);
#else
        fseeko(probe, 0, SEEK_END);
        const int64_t len = ftello(probe);
#endif
        fclose(probe);
        if (len >= kLogMaxBytes) {
          remove(prev.c_str());
          rename(current.c_str(), prev.c_str());  // rotate: keep ONE generation
        }
      }
    }
    out = fopen(current.c_str(), truncate ? "wb" : "ab");
    written = 0;
  };
  reopen(false);
  if (out) {
    char stamp[40];
    const time_t now = time(nullptr);
    struct tm tmv {};
#ifdef _WIN32
    localtime_s(&tmv, &now);
#else
    localtime_r(&now, &tmv);
#endif
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
    fprintf(out, "\n=== AETHONE session %s ===\n", stamp);
    fflush(out);
  }
  char buf[64 * 1024];
  for (;;) {
    const auto n =
#ifdef _WIN32
        _read(read_fd, buf, sizeof(buf));
#else
        read(read_fd, buf, sizeof(buf));
#endif
    if (n <= 0) break;
    {
      std::lock_guard<std::mutex> lock(g_log_clear_mutex);
      if (g_log_clear_requested) {
        g_log_clear_requested = false;
        reopen(true);  // consumed on the next chunk (single-writer)
      } else if (written >= kLogMaxBytes) {
        reopen(false);
      }
    }
    if (!out) reopen(true);
    if (out && n > 0) {
      fwrite(buf, 1, static_cast<size_t>(n), out);
      written += n;
      fflush(out);
    }
  }
  if (out) fclose(out);
}

}  // namespace

// ------------------------------------------------------------------ paths --
const DesktopPaths& Paths() {
  static DesktopPaths cached;
  static std::once_flag once;
  std::call_once(once, [] {
    const std::string exe = ExePath();
    cached.exeDir = DirName(exe);
    cached.filesDir = HomeDataDir();
    MkDirAll(cached.filesDir);
#ifdef _WIN32
    // Everything lives beside the executable; the DLL search order finds it.
    cached.aetherLib = cached.exeDir + "\\aether.dll";
    cached.zeptunLib = cached.exeDir + "\\zeptun.dll";
    cached.lyrebirdBin = cached.exeDir + "\\lyrebird.exe";
    cached.psiphonBin = cached.exeDir + "\\psiphon.exe";
#else
    // Flutter's linux bundle convention: shared libraries under lib/.
    // The executable's INSTALL_RPATH is $ORIGIN/lib (linux/CMakeLists.txt).
    cached.aetherLib = cached.exeDir + "/lib/libaether.so";
    cached.zeptunLib = cached.exeDir + "/lib/libzeptun.so";
    cached.lyrebirdBin = cached.exeDir + "/lyrebird";
    cached.psiphonBin = cached.exeDir + "/psiphon";
#endif
  });
  return cached;
}

std::string PreloadAetherLibrary() {
#ifndef _WIN32
  const std::string& path = Paths().aetherLib;
  if (!PathExists(path)) {
    return std::string("libaether.so missing from the bundle (") + path + ")";
  }
  if (dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL) == nullptr) {
    const char* why = dlerror();
    return std::string("dlopen ") + path + " failed: " + (why ? why : "?");
  }
  return "";
#else
  // Windows: LoadLibrary searches the application directory first — the
  // Dart side's DynamicLibrary.open('aether.dll') finds it natively. Nothing
  // to preload; existence is checked (the file must ship in the bundle).
  if (!PathExists(Paths().aetherLib)) {
    return std::string("aether.dll missing from the bundle (") +
           Paths().aetherLib + ")";
  }
  return "";
#endif
}

std::string LoadZeptunLibrary() {
  std::call_once(g_zeptun_once, LoadZeptunOnce);
  return g_zeptun_error;
}

bool ZeptunLibraryLoaded() {
  std::call_once(g_zeptun_once, LoadZeptunOnce);
  return g_zeptun.handle != nullptr;
}

// -------------------------------------------------------------- core log --
void InstallCoreLogCapture() {
  if (g_log_installed) return;
  const DesktopPaths& p = Paths();
  g_log_dir = p.filesDir + "/logs";
  MkDirAll(g_log_dir);
  g_log_path = g_log_dir + "/core-log.txt";
  g_log_prev = g_log_dir + "/core-log.1.txt";
  // v4.34 decree: every process starts with an EMPTY capture (a force-killed
  // session leaves no residue either).
  remove(g_log_path.c_str());
  remove(g_log_prev.c_str());

#ifdef _WIN32
  int fds[2];
  if (_pipe(fds, 64 * 1024, _O_BINARY) != 0) return;
  const int read_fd = fds[0];
  const int write_fd = fds[1];
#else
  int fds[2];
  if (pipe(fds) != 0) return;
  const int read_fd = fds[0];
  const int write_fd = fds[1];
#endif
  std::thread(LogReaderLoop, read_fd).detach();
  // Redirect the process stdout+stderr onto the pipe. The embedded Rust core
  // (aether) writes its env_logger output to fd 2 — the whole point of the
  // capture (the Kotlin layer does the same with Os.dup2).
#ifdef _WIN32
  _dup2(write_fd, 1);
  _dup2(write_fd, 2);
  _close(write_fd);  // the reader keeps fds[0]; the write end lives as 1 & 2
#else
  dup2(write_fd, 1);
  dup2(write_fd, 2);
  close(write_fd);
#endif
  g_log_installed = true;
}

std::string ReadCoreLogTail(int tailBytes, int64_t* totalBytesOut) {
  int64_t& total = *totalBytesOut;
  total = 0;
  if (tailBytes < 1024) tailBytes = 1024;
  if (tailBytes > 1024 * 1024) tailBytes = 1024 * 1024;

  int64_t currentLen = 0, prevLen = 0;
  {
    FILE* f = fopen(g_log_path.c_str(), "rb");
    if (f) {
#ifdef _WIN32
      _fseeki64(f, 0, SEEK_END);
      currentLen = _ftelli64(f);
#else
      fseeko(f, 0, SEEK_END);
      currentLen = ftello(f);
#endif
      fclose(f);
    }
    f = fopen(g_log_prev.c_str(), "rb");
    if (f) {
#ifdef _WIN32
      _fseeki64(f, 0, SEEK_END);
      prevLen = _ftelli64(f);
#else
      fseeko(f, 0, SEEK_END);
      prevLen = ftello(f);
#endif
      fclose(f);
    }
  }
  total = currentLen + prevLen;

  const int64_t tail = tailBytes;
  int64_t fromPrev = tail - currentLen;
  if (fromPrev < 0) fromPrev = 0;
  if (fromPrev > prevLen) fromPrev = prevLen;
  std::string out;
  out.reserve(static_cast<size_t>(tail));
  if (fromPrev > 0) {
    FILE* f = fopen(g_log_prev.c_str(), "rb");
    if (f) {
#ifdef _WIN32
      _fseeki64(f, prevLen - fromPrev, SEEK_SET);
#else
      fseeko(f, prevLen - fromPrev, SEEK_SET);
#endif
      std::string chunk(static_cast<size_t>(fromPrev), '\0');
      const size_t got = fread(&chunk[0], 1, chunk.size(), f);
      out.append(chunk, 0, got);
      fclose(f);
    }
  }
  FILE* f = fopen(g_log_path.c_str(), "rb");
  if (f) {
    const int64_t currentFrom = currentLen - (tail - fromPrev);
#ifdef _WIN32
    _fseeki64(f, currentFrom < 0 ? 0 : currentFrom, SEEK_SET);
#else
    fseeko(f, currentFrom < 0 ? 0 : currentFrom, SEEK_SET);
#endif
    std::string chunk(static_cast<size_t>(
                          currentLen - (currentFrom < 0 ? 0 : currentFrom)),
                      '\0');
    const size_t got = fread(&chunk[0], 1, chunk.size(), f);
    out.append(chunk, 0, got);
    fclose(f);
  }
  return out;
}

void ClearCoreLog() {
  std::lock_guard<std::mutex> lock(g_log_clear_mutex);
  g_log_clear_requested = true;
  remove(g_log_path.c_str());
  remove(g_log_prev.c_str());
}

// ------------------------------------------------------------- core job --
void SetCoreJob(int64_t job) {
  std::lock_guard<std::mutex> lock(g_core_job_mutex);
  g_core_job = job;
}
int64_t GetCoreJob() {
  std::lock_guard<std::mutex> lock(g_core_job_mutex);
  return g_core_job;
}
void ClearCoreJob() {
  std::lock_guard<std::mutex> lock(g_core_job_mutex);
  g_core_job = 0;
}

// ---------------------------------------------------------------- tunnel --
TunnelStartResult StartTunnel(int port, int session, bool tcpOnly) {
  std::lock_guard<std::mutex> lock(g_tunnel_mutex);
  TunnelStartResult res{TunnelStartKind::kError, ""};

  // The straggler gate (the v4.26 Kotlin lesson): a start superseded by a
  // newer stop refuses to establish — nobody owns the TUN it would create.
  if (session != 0 && session <= g_tunnel.stopGeneration) {
    res.kind = TunnelStartKind::kStaleSession;
    res.reason = "stale-start";
    return res;
  }

  // A different target (port / udp mode) is a full restart, exactly like the
  // Kotlin port-change branch; the same target is the plain re-entry.
  if (g_tunnel.up) {
    if (port != g_tunnel.port || tcpOnly != g_tunnel.tcpOnly) {
      Zeptun* old = g_tunnel.engine;
      g_tunnel.engine = nullptr;
      g_tunnel.up = false;
      if (old) {
        if (g_zeptun.stop) g_zeptun.stop(old);
        if (g_zeptun.destroy) g_zeptun.destroy(old);
      }
    } else {
      res.kind = TunnelStartKind::kOk;
      return res;  // already serving this exact target
    }
  }

  const std::string load_err = LoadZeptunLibrary();
  if (!load_err.empty()) {
    res.reason = "zeptun-library-missing: " + load_err;
    return res;
  }

  const std::string toml = BuildZeptunToml(port, tcpOnly);
  Zeptun* engine = nullptr;
  const int rc = g_zeptun.create_from_toml(toml.c_str(), toml.size(), &engine);
  if (rc != ZEPTUN_OK || engine == nullptr) {
    res.reason = std::string("zeptun-start-failed:rc=") + std::to_string(rc) +
                 " (" + (g_zeptun.strerror_ ? g_zeptun.strerror_(rc) : "?") +
                 ")";
    return res;
  }
  const int rc2 = g_zeptun.start(engine);
  if (rc2 != ZEPTUN_OK) {
    g_zeptun.destroy(engine);
    res.reason = std::string("zeptun-start-failed:rc=") + std::to_string(rc2) +
                 " (" + (g_zeptun.strerror_ ? g_zeptun.strerror_(rc2) : "?") +
                 ")";
    return res;
  }
  g_tunnel.engine = engine;
  g_tunnel.up = true;
  g_tunnel.port = port;
  g_tunnel.tcpOnly = tcpOnly;
  g_tunnel.session = session;
  if (session > g_tunnel.liveSession) g_tunnel.liveSession = session;
  res.kind = TunnelStartKind::kOk;
  return res;
}

int StopTunnel() {
  std::lock_guard<std::mutex> lock(g_tunnel_mutex);
  if (g_tunnel.liveSession > g_tunnel.stopGeneration) {
    g_tunnel.stopGeneration = g_tunnel.liveSession;
  }
  Zeptun* engine = g_tunnel.engine;
  g_tunnel.engine = nullptr;
  g_tunnel.up = false;
  if (engine) {
    if (g_zeptun.stop) g_zeptun.stop(engine);  // idempotent by bridge design
    if (g_zeptun.destroy) g_zeptun.destroy(engine);
  }
  return g_tunnel.session;
}

TunnelCounters ReadTunnelCounters() {
  std::lock_guard<std::mutex> lock(g_tunnel_mutex);
  TunnelCounters out{false, 0, -1, -1};
  if (!g_tunnel.up || g_tunnel.engine == nullptr) return out;
  ZeptunStats stats{};
  if (g_zeptun.stats && g_zeptun.stats(g_tunnel.engine, &stats) == ZEPTUN_OK) {
    out.running = true;
    out.port = g_tunnel.port;
    // include/zeptun.h field order: 0 rx_packets, 1 rx_bytes, 2 tx_packets,
    // 3 tx_bytes — TUN rx = upload, TUN tx = download (the Kotlin mapping).
    out.rxBytes = static_cast<int64_t>(stats.rx_bytes);
    out.txBytes = static_cast<int64_t>(stats.tx_bytes);
  }
  return out;
}

}  // namespace aethone
