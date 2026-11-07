// desktop_engine.cpp — see desktop_shared/desktop_engine.h for the contract.
// Pure C++17, no Flutter headers: both runners link this once.
#include "desktop_engine.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#include <cwchar>
#include <direct.h>
#include <fcntl.h>
#include <io.h>
#include <objbase.h>
#include <shlobj.h>
#include <wininet.h>
#include <windows.h>
#define GETCWD _getcwd
// v4.39 — the Windows path layer is UTF-8 end-to-end: every path the
// engine layer builds travels as UTF-8 and converts through
// MultiByteToWideChar(CP_UTF8) exactly once, at the Win32 boundary.
#define MKDIR(p) _wmkdir(Utf8ToWide(p).c_str())
#else
#include <arpa/inet.h>
#include <dlfcn.h>
#include <fcntl.h>  // O_RDONLY
#include <pwd.h>    // v4.40 — getpwnam(SUDO_USER): the autostart lands in the
                    // desktop session user's config, not root's
#include <signal.h>
#include <spawn.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
#define GETCWD getcwd
#define MKDIR(p) mkdir(p, 0755)
extern char** environ;
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
  int (*set_log_callback)(zeptun_log_cb, void*, int) = nullptr;
};

ZeptunApi g_zeptun;
std::once_flag g_zeptun_once;
std::string g_zeptun_error;

// v4.40 — the zeptun log bridge. Up to and including r86 the tunnel library
// logged into a NULL sink (zeptun's log.zig: `sink orelse return`), so the
// single most diagnostic line of a failed Windows bring-up — wintun.zig's
// "wintun: cannot open or create adapter … (error N)" — was thrown away and
// the owner's screen showed only the generic "rc=-5 (device error)". The
// callback below fwrites every line to stderr, which InstallCoreLogCapture
// has already dup2'd onto the core log — the lines become visible in the
// in-app core log AND feed the error augmentation in BringUpZeptun. The last
// few lines are also kept in a small ring buffer (mutex-guarded) so a failed
// start can quote the exact wintun/zeptun error in the tunnelStartFailed
// reason the failure screen shows.
std::mutex g_zeptun_log_mutex;
std::deque<std::string> g_zeptun_log_tail;

void ZeptunLogLine(int level, const char* message, size_t len) {
  if (message == nullptr || len == 0) return;
  std::string line(message, strnlen(message, len));
  static const char* kTag[] = {"[zeptun err] ", "[zeptun warn] ",
                               "[zeptun info] ", "[zeptun debug] ",
                               "[zeptun trace] "};
  const char* tag = kTag[(level >= 0 && level <= 4) ? level : 1];
  {
    std::lock_guard<std::mutex> lock(g_zeptun_log_mutex);
    g_zeptun_log_tail.push_back(line);
    while (g_zeptun_log_tail.size() > 16) g_zeptun_log_tail.pop_front();
  }
  // stderr here IS the captured core log (dup2'd before any engine work).
  fflush(stdout);
  fprintf(stderr, "%s%s\n", tag, line.c_str());
  fflush(stderr);
}

// The last zeptun line that names a bring-up failure (wintun/route/config) —
// quoted into the start error so the real Windows error code reaches the
// owner's screen (the strerror of rc=-5 is only "device error").
std::string LastZeptunFailureLine() {
  std::lock_guard<std::mutex> lock(g_zeptun_log_mutex);
  for (auto it = g_zeptun_log_tail.rbegin(); it != g_zeptun_log_tail.rend();
       ++it) {
    if (it->rfind("wintun:", 0) == 0 || it->rfind("route:", 0) == 0 ||
        it->rfind("tun:", 0) == 0 || it->rfind("device:", 0) == 0) {
      return *it;
    }
  }
  return std::string();
}

#ifdef _WIN32
// v4.39 — the UTF-8/W boundary helpers. The v4.36 code used the ANSI
// entry points (GetModuleFileNameA / SHGetFolderPathA / GetFileAttributesA
// / fopen) and, at LoadLibrary time, widened with
// std::wstring(str.begin(), str.end()) — a byte-wise widening that is only
// correct for pure ASCII. The owner's device test of the r85 Windows
// bundle hit exactly that: a non-ASCII install path (a Persian user name
// or extract folder) widens to garbage and LoadLibraryExW reports 126 —
// ERROR_MOD_NOT_FOUND, "LoadLibrary zeptun.dll failed (126)" — while the
// very same bundle works under an ASCII path. Every path below is UTF-8
// in the C++ layer and converts exactly once, here.
std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int need = MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                       static_cast<int>(s.size()), nullptr, 0);
  if (need <= 0) return std::wstring();
  std::wstring w(static_cast<size_t>(need), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      &w[0], need);
  return w;
}
std::string WideToUtf8(const wchar_t* w, size_t n) {
  if (w == nullptr || n == 0) return std::string();
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, w, static_cast<int>(n),
                                        nullptr, 0, nullptr, nullptr);
  if (bytes <= 0) return std::string();
  std::string s(static_cast<size_t>(bytes), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w, static_cast<int>(n), &s[0], bytes,
                      nullptr, nullptr);
  return s;
}
#endif  // _WIN32

// v4.39 — codepage-safe file helpers for the captured-core-log paths (the
// filesDir can carry non-ASCII; the ANSI CRT entry points would miss the
// very files the W layer just created). Linux keeps the POSIX calls.
std::FILE* FileOpen(const std::string& path, const char* mode) {
#ifdef _WIN32
  return _wfopen(Utf8ToWide(path).c_str(), Utf8ToWide(mode).c_str());
#else
  return fopen(path.c_str(), mode);
#endif
}
int FileRemove(const std::string& path) {
#ifdef _WIN32
  return _wremove(Utf8ToWide(path).c_str());
#else
  return remove(path.c_str());
#endif
}
int FileRename(const std::string& from, const std::string& to) {
#ifdef _WIN32
  return _wrename(Utf8ToWide(from).c_str(), Utf8ToWide(to).c_str());
#else
  return rename(from.c_str(), to.c_str());
#endif
}

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
  // v4.39 — the wide path comes through the CP_UTF8 boundary (the v4.36
  // byte-widening broke every non-ASCII install path: LoadLibrary reported
  // 126 while the DLL sat right beside aethone.exe). The absolute path
  // keeps the load independent of the CWD; APPLICATION_DIR resolves
  // zeptun.dll's own imports against the bundle first.
  const std::wstring wide = Utf8ToWide(p.zeptunLib);
  HMODULE lib = LoadLibraryExW(  // NOLINT: wide string on Windows
      wide.c_str(), nullptr, LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
  if (lib == nullptr) {
    // A second chance with the altered search path — some downlevel
    // Windows builds mishandle the flag combination on absolute paths;
    // never a reason to fail silently.
    lib = LoadLibraryExW(wide.c_str(), nullptr,
                         LOAD_WITH_ALTERED_SEARCH_PATH);
  }
  if (lib == nullptr) {
    char buf[200];
    snprintf(buf, sizeof(buf),
             "LoadLibrary zeptun.dll failed (%lu) at %s — is the DLL "
             "shipped beside aethone.exe?",
             GetLastError(), p.zeptunLib.c_str());
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
  g_zeptun.set_log_callback =
      Sym<decltype(g_zeptun.set_log_callback)>(g_zeptun.handle,
                                               "zeptun_set_log_callback");
  if (!g_zeptun.create_from_toml || !g_zeptun.start || !g_zeptun.stop ||
      !g_zeptun.destroy || !g_zeptun.stats || !g_zeptun.strerror_) {
    g_zeptun_error = "zeptun shared library is missing required symbols";
    g_zeptun = ZeptunApi{};  // refuse a half-loaded engine
    return;
  }
  // v4.40 — route zeptun's own log into the captured core log (see
  // ZeptunLogLine). set_log_callback may be absent in an older pin — the
  // bridge is then simply inactive (the required symbols above already
  // gated the load).
  if (g_zeptun.set_log_callback != nullptr) {
    g_zeptun.set_log_callback(
        [](void*, int level, const char* msg, size_t len) {
          ZeptunLogLine(level, msg, len);
        },
        nullptr, /*level=*/2 /*err+warn+info*/);
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

#ifndef _WIN32
// ---- v4.37: the Linux privilege helper client --------------------------------
// (path helpers MkDirAll/PathExists are declared later in this file —
// forward-declared here so the client can sit next to the tunnel state)
bool PathExists(const std::string& p);
void MkDirAll(const std::string& path);

// The state of the pkexec-launched aethone-tunnel-helper (one per connect).
struct HelperState {
  int sock = -1;             // the live client socket (>= 0 while serving)
  int tun_fd = -1;           // the TUN fd we adopted (closed with the tunnel)
  pid_t pid = -1;            // pkexec/helper process (reaped lazily)
  std::string sockPath;
  std::string logPath;       // <filesDir>/logs/helper-log.txt (root appends)
};
HelperState g_helper;
std::mutex g_helper_mutex;

TunnelEventSink g_tunnel_sink = nullptr;
void* g_tunnel_sink_ctx = nullptr;
std::atomic<int> g_async_stop_gen{0};   // stop generations during async bring-up
std::atomic<bool> g_async_bringing{false};

void EmitTunnelEvent(bool up, int port, int session, const std::string& reason) {
  if (g_tunnel_sink == nullptr) return;
  TunnelEvent e;
  e.up = up;
  e.port = port;
  e.session = session;
  e.reason = reason;
  g_tunnel_sink(g_tunnel_sink_ctx, e);
}

std::string HelperLogLine(const std::string& what) {
  char stamp[40];
  const time_t now = time(nullptr);
  struct tm tmv;
  localtime_r(&now, &tmv);
  strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
  return std::string("[") + stamp + "] desktop-engine: " + what + "\n";
}

// The helper's own stderr lands in its own separable log file (the owner's
// logging decree: aether / zeptun / helper logs must stay distinguishable).
void HelperLog(const std::string& line) {
  const std::string& path = g_helper.logPath;
  if (path.empty()) return;
  FILE* f = fopen(path.c_str(), "ab");
  if (f == nullptr) return;
  fwrite(line.data(), 1, line.size(), f);
  fclose(f);
}

// Where the system-installed helper must live. pkexec only executes
// root-owned paths, so the BUNDLED helper installs itself there on first
// connect (pkexec /usr/bin/env <bundle> --self-install — ONE prompt).
static const char* kHelperInstallPath = "/usr/libexec/aethone-tunnel-helper";
static const char* kHelperPolicyInstallPath =
    "/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy";

bool HelperInstalled() {
  struct stat st;
  return stat(kHelperInstallPath, &st) == 0 && S_ISREG(st.st_mode) &&
         st.st_uid == 0 && (st.st_mode & 0222) == 0 &&
         access(kHelperInstallPath, X_OK) == 0 &&
         stat(kHelperPolicyInstallPath, &st) == 0;
}

// One pkexec round: /usr/bin/env (a root-owned system binary — pkexec's
// refusal to execute user-writable BUNDLE paths does not apply to it) runs
// the bundled helper as root, whose --self-install copies itself to
// /usr/libexec and writes the Polkit action, verifying both (fail-closed).
bool EnsureHelperInstalled(std::string* err) {
  if (HelperInstalled()) return true;
  const DesktopPaths& p = Paths();
  if (p.helperBin.empty() || access(p.helperBin.c_str(), X_OK) != 0) {
    *err = "the privilege helper is missing from the bundle (" + p.helperBin +
           ") — is this a complete desktop bundle?";
    return false;
  }
  const char* env_exe = access("/usr/bin/env", X_OK) == 0 ? "/usr/bin/env"
                                                          : "/bin/env";
  if (access(env_exe, X_OK) != 0) {
    *err = "/usr/bin/env is not available — cannot bootstrap the privilege "
           "helper on this system";
    return false;
  }
  const char* pkexec = access("/usr/bin/pkexec", X_OK) == 0
                           ? "/usr/bin/pkexec"
                           : "/bin/pkexec";
  if (access(pkexec, X_OK) != 0) {
    *err = "pkexec (polkit) is not available — install policykit-1 to use "
           "the tunnel mode, or run the app from an administrator session";
    return false;
  }
  char self_install[] = "--self-install";
  char* const argv[] = {const_cast<char*>(env_exe),
                        const_cast<char*>(p.helperBin.c_str()), self_install,
                        nullptr};
  HelperLog(HelperLogLine("bootstrap: installing the privilege helper + Polkit "
                          "action (one pkexec password prompt)"));
  pid_t pid = -1;
  if (posix_spawn(&pid, pkexec, nullptr, nullptr, argv, environ) != 0) {
    *err = "spawning pkexec failed";
    return false;
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    *err = "waiting for pkexec failed";
    return false;
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    const int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    if (code == 126) {
      *err = "the administrator permission was declined (polkit) — the tunnel "
             "cannot be set up without it";
    } else if (code == 127) {
      *err = "pkexec failed to run the installer (127) — is policykit-1 "
             "installed and a polkit agent active?";
    } else {
      *err = "installing the privilege helper failed (exit " +
             std::to_string(code) + ")";
    }
    return false;
  }
  if (!HelperInstalled()) {
    *err = "the helper did not land at " + std::string(kHelperInstallPath) +
           " after installation";
    return false;
  }
  HelperLog(HelperLogLine("bootstrap: helper installed system-wide"));
  return true;
}

// Spawns `pkexec aethone-tunnel-helper --serve <sock>` and connects.
// `stop_gen` is the async stop generation at bring-up entry — a disconnect
// during the Polkit dialog cancels the wait instead of hanging for minutes.
//
// LOCK DISCIPLINE (the deadlock lesson): the LONG waits (spawn → socket →
// connect, up to 180 s while the user stares at the password prompt) run
// WITHOUT g_helper_mutex — only the brief state updates take it. A single
// bring-up worker exists at a time (g_async_bringing), so the unlocked
// stretches are worker-owned; StopTunnel's teardown may race them and the
// worker treats every failed step as a clean abort.
bool StartHelper(int stop_gen, std::string* err) {
  {
    std::lock_guard<std::mutex> lock(g_helper_mutex);
    if (g_helper.sock >= 0) return true;  // already serving
  }

  // The socket lives in the user's runtime dir (0700, user-owned) — the
  // helper refuses root-owned socket dirs and checks SO_PEERCRED against
  // the directory's owner.
  const char* xdg = getenv("XDG_RUNTIME_DIR");
  std::string dir;
  if (xdg && *xdg) {
    dir = std::string(xdg) + "/aethone";
  } else {
    dir = "/tmp/aethone-helper-" + std::to_string(static_cast<long>(getuid()));
  }
  MkDirAll(dir);
  chmod(dir.c_str(), 0700);
  const std::string path = dir + "/tunnel-helper.sock";
  unlink(path.c_str());  // a stale socket from a crashed pair
  {
    std::lock_guard<std::mutex> lock(g_helper_mutex);
    g_helper.sockPath = path;
    g_helper.logPath = Paths().filesDir + "/logs/helper-log.txt";
  }

  // The helper's stderr → its own log file (created by US, appended by root
  // through the inherited descriptor — the app can read it back).
  const int log_fd = open(g_helper.logPath.c_str(),
                          O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
  posix_spawn_file_actions_t fa;
  posix_spawn_file_actions_init(&fa);
  if (log_fd >= 0) {
    posix_spawn_file_actions_adddup2(&fa, log_fd, 1);
    posix_spawn_file_actions_adddup2(&fa, log_fd, 2);
  }
  char sock_arg[256];
  snprintf(sock_arg, sizeof(sock_arg), "%s", path.c_str());
  const char* pkexec = access("/usr/bin/pkexec", X_OK) == 0
                           ? "/usr/bin/pkexec"
                           : "/bin/pkexec";
  char* const argv[] = {const_cast<char*>("pkexec"),
                        const_cast<char*>(kHelperInstallPath),
                        const_cast<char*>("--serve"), sock_arg, nullptr};
  pid_t pid = -1;
  const int rc = posix_spawn(&pid, pkexec, &fa, nullptr, argv, environ);
  posix_spawn_file_actions_destroy(&fa);
  if (log_fd >= 0) close(log_fd);
  if (rc != 0) {
    *err = "spawning the privilege helper failed";
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_helper_mutex);
    g_helper.pid = pid;
  }

  // Wait for the socket (pkexec may sit on a password prompt for minutes —
  // the Dart walk's Linux tunnelUp budget covers it) and connect. NO lock:
  // a concurrent StopTunnel must stay responsive.
  const int kWaitMs = 180000;  // mirrors the Android permission budget
  bool appeared = false;
  for (int waited = 0; waited < kWaitMs; waited += 100) {
    struct stat st;
    if (stat(path.c_str(), &st) == 0) {
      appeared = true;
      break;
    }
    if (g_async_stop_gen.load() != stop_gen) {
      kill(pid, SIGTERM);  // cancel the dialog; the walk already ended
      *err = "cancelled while waiting for the privilege prompt";
      return false;
    }
    usleep(100 * 1000);
  }
  if (!appeared) {
    *err = "the privilege helper did not come up (did the polkit password "
           "prompt appear? is a polkit authentication agent running?)";
    kill(pid, SIGTERM);
    return false;
  }
  int sock = -1;
  for (int waited = 0; waited < 10000 && sock < 0; waited += 200) {
    sock = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (sock >= 0) {
      sockaddr_un sa;
      memset(&sa, 0, sizeof(sa));
      sa.sun_family = AF_UNIX;
      strncpy(sa.sun_path, path.c_str(), sizeof(sa.sun_path) - 1);
      if (connect(sock, reinterpret_cast<sockaddr*>(&sa), sizeof(sa)) != 0) {
        close(sock);
        sock = -1;
        usleep(200 * 1000);
      }
    }
  }
  if (sock < 0) {
    *err = "could not connect to the privilege helper";
    kill(pid, SIGTERM);
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_helper_mutex);
    g_helper.sock = sock;
  }
  HelperLog(HelperLogLine("helper: connected (pkexec pid " +
                          std::to_string(static_cast<long>(pid)) + ")"));
  return true;
}

// One request → one reply line, optionally receiving an fd (SCM_RIGHTS).
bool HelperRequest(const char* cmd, std::string* reply, int* fd_out) {
  std::lock_guard<std::mutex> lock(g_helper_mutex);
  if (g_helper.sock < 0) {
    *reply = "ERR helper is not running";
    return false;
  }
  const std::string line = std::string(cmd) + "\n";
  if (write(g_helper.sock, line.data(), line.size()) !=
      static_cast<ssize_t>(line.size())) {
    *reply = "ERR writing to the helper failed";
    return false;
  }
  char buf[512];
  iovec iov{buf, sizeof(buf) - 1};
  char control[64];
  msghdr msg;
  memset(&msg, 0, sizeof(msg));
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = control;
  msg.msg_controllen = sizeof(control);
  const ssize_t n = recvmsg(g_helper.sock, &msg, 0);
  if (n <= 0) {
    *reply = "ERR the helper closed the connection";
    return false;
  }
  buf[n] = 0;
  *reply = buf;
  if (fd_out != nullptr) *fd_out = -1;
  for (cmsghdr* ch = CMSG_FIRSTHDR(&msg); ch != nullptr;
       ch = CMSG_NXTHDR(&msg, ch)) {
    if (ch->cmsg_level == SOL_SOCKET && ch->cmsg_type == SCM_RIGHTS &&
        ch->cmsg_len >= CMSG_LEN(sizeof(int))) {
      int got = -1;
      memcpy(&got, CMSG_DATA(ch), sizeof(int));
      if (fd_out != nullptr) {
        *fd_out = got;
      } else {
        close(got);
      }
    }
  }
  return reply->rfind("OK", 0) == 0;
}

// Tears the helper pair down: sends `down` (the helper reverts routes/rules/
// resolved on it OR on EOF), closes the socket and the adopted fd, and reaps
// the process from a detached thread. Idempotent; takes g_helper_mutex only
// for the brief state swap (never blocks: the long waits in StartHelper run
// unlocked — the deadlock lesson).
void StopHelperPair() {
  int sock = -1, tun_fd = -1;
  pid_t pid = -1;
  {
    std::lock_guard<std::mutex> lock(g_helper_mutex);
    sock = g_helper.sock;
    g_helper.sock = -1;
    tun_fd = g_helper.tun_fd;
    g_helper.tun_fd = -1;
    pid = g_helper.pid;
    g_helper.pid = -1;
  }
  if (sock >= 0) {
    // best-effort `down` (EOF triggers the same teardown in the helper)
    (void)!write(sock, "down\n", 5);
    shutdown(sock, SHUT_RDWR);
    close(sock);
  }
  if (tun_fd >= 0) {
    close(tun_fd);  // the interface dies with the last fd
  }
  if (pid > 0) {
    std::thread([pid] {
      for (int i = 0; i < 50; ++i) {
        if (waitpid(pid, nullptr, WNOHANG) == pid) return;
        usleep(100 * 1000);
      }
      kill(pid, SIGKILL);
      waitpid(pid, nullptr, 0);
    }).detach();
  }
}
#endif  // !_WIN32

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
  // v4.39 — W entry point: the v4.36 GetFileAttributesA misread every
  // non-ASCII path (same class as the LoadLibrary 126).
  return GetFileAttributesW(Utf8ToWide(p).c_str()) != INVALID_FILE_ATTRIBUTES;
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
  wchar_t buf[MAX_PATH];
  const DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
  return n > 0 ? WideToUtf8(buf, n) : std::string("aethone.exe");
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
  wchar_t roaming[MAX_PATH];
  if (SUCCEEDED(
          SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, roaming))) {
    return WideToUtf8(roaming, wcslen(roaming)) + "\\aethone";
  }
  wchar_t buf[MAX_PATH];
  if (_wgetcwd(buf, MAX_PATH)) {
    return WideToUtf8(buf, wcslen(buf)) + "\\aethone";
  }
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

std::string BuildZeptunToml(int port, bool tcpOnly, bool socksStrict) {
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
  // v4.38 — the psiphon tunnel data-path fix (the round-13 addendum defect,
  // every version: proxy worked, tunnel showed Connected with no data).
  // The psiphon family's SOCKS target is psiphon-tunnel-core's goptlib
  // server; its socksFlushReadBuffer (psiphon/common/goptlib/socks.go)
  // rejects ANY byte buffered after a SOCKS message. zeptun's defaults
  // pipeline the handshake (greeting+request in one write — and pooled
  // connections always) and attach optimistic data, so every TCP flow of
  // the psiphon tunnel died at the handshake while the sequential probe
  // passed. Strict mode = a fully sequential SOCKS5 client (same keys as
  // the Kotlin + Dart builders; byte-level proof:
  // scripts/psiphon_socks_pipeline_check.py).
  if (socksStrict) {
    doc += "pipeline = false\n";
    doc += "optimistic_data = false\n";
  }
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

#ifndef _WIN32
// v4.37 — the HELPER-mode TOML: the privileged bring-up (TUN + address +
// MTU + policy routes/rules + the resolved DNS delegation) was ALREADY done
// by aethone-tunnel-helper, which handed us the open TUN fd. zeptun adopts
// it in .fd mode (the Android VpnService model: raw IP packets, one queue,
// no vnet header) and runs the UNPRIVILEGED data plane only. The route
// section is intentionally absent — RouteConfig.auto_route defaults to false
// and the rules live in the helper's table 2022 (config keys per the frozen
// pin: tun.fd sets device.kind = .fd, tun.configure skips the link setup).
std::string BuildZeptunTomlFd(int port, bool tcpOnly, int fd, bool socksStrict) {
  std::string doc;
  doc.reserve(300);
  doc += "preset = \"desktop\"\n";
  doc += "\n[tun]\n";
  doc += "fd = ";
  doc += std::to_string(fd);
  doc += "\n";
  doc += "configure = false\n";
  doc += "\n[handler]\n";
  doc += "kind = \"socks5\"\n";
  doc += "\n[handler.socks5]\n";
  doc += "server = \"127.0.0.1:";
  doc += std::to_string(port);
  doc += "\"\n";
  if (tcpOnly) doc += "udp = false\n";
  // v4.38 — the psiphon strict-socks keys, identical to BuildZeptunToml
  // (the helper path serves the same psiphon family; see the comment there).
  if (socksStrict) {
    doc += "pipeline = false\n";
    doc += "optimistic_data = false\n";
  }
  doc += "\n[dns]\n";
  doc += "fake_ip = true\n";
  return doc;
}
#endif  // !_WIN32

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
      FILE* probe = FileOpen(current, "rb");
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
          FileRemove(prev);
          FileRename(current, prev);  // rotate: keep ONE generation
        }
      }
    }
    out = FileOpen(current, truncate ? "wb" : "ab");
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
    // The privilege helper is a Linux concept (Polkit); Windows keeps its
    // own requireAdministrator manifest model — both stay empty here.
#else
    // Flutter's linux bundle convention: shared libraries under lib/.
    // The executable's INSTALL_RPATH is $ORIGIN/lib (linux/CMakeLists.txt).
    cached.aetherLib = cached.exeDir + "/lib/libaether.so";
    cached.zeptunLib = cached.exeDir + "/lib/libzeptun.so";
    cached.lyrebirdBin = cached.exeDir + "/lyrebird";
    cached.psiphonBin = cached.exeDir + "/psiphon";
    // v4.37 — the bundled privilege helper + its Polkit action, shipped in
    // the bundle root by linux/CMakeLists.txt (installed system-wide on the
    // first tunnel connect; see EnsureHelperInstalled).
    cached.helperBin = cached.exeDir + "/aethone-tunnel-helper";
    cached.helperPolicy =
        cached.exeDir + "/com.chakcaad.aethone.tunnel-helper.policy";
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
  FileRemove(g_log_path);
  FileRemove(g_log_prev);

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
    FILE* f = FileOpen(g_log_path, "rb");
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
    f = FileOpen(g_log_prev, "rb");
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
  FILE* f = FileOpen(g_log_path, "rb");
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
  FileRemove(g_log_path);
  FileRemove(g_log_prev);
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
namespace {

// The shared zeptun bring-up: TOML in, engine up (or the honest error).
TunnelStartResult BringUpZeptun(const std::string& toml) {
  TunnelStartResult res{TunnelStartKind::kError, ""};
  const std::string load_err = LoadZeptunLibrary();
  if (!load_err.empty()) {
    res.reason = "zeptun-library-missing: " + load_err;
    return res;
  }
  Zeptun* engine = nullptr;
  const int rc = g_zeptun.create_from_toml(toml.c_str(), toml.size(), &engine);
  if (rc != ZEPTUN_OK || engine == nullptr) {
    res.reason = std::string("zeptun-start-failed:rc=") + std::to_string(rc) +
                 " (" + (g_zeptun.strerror_ ? g_zeptun.strerror_(rc) : "?") +
                 ")";
    // v4.40 — quote the tunnel library's own failure line (the wintun
    // error code) into the reason: "rc=-5 (device error)" alone never told
    // the owner WHAT failed; with the log bridge the exact Windows error
    // (adapter creation, driver install, …) reaches the failure screen.
    const std::string detail = LastZeptunFailureLine();
    if (!detail.empty()) res.reason += " [" + detail + "]";
    return res;
  }
  const int rc2 = g_zeptun.start(engine);
  if (rc2 != ZEPTUN_OK) {
    g_zeptun.destroy(engine);
    res.reason = std::string("zeptun-start-failed:rc=") + std::to_string(rc2) +
                 " (" + (g_zeptun.strerror_ ? g_zeptun.strerror_(rc2) : "?") +
                 ")";
    const std::string detail2 = LastZeptunFailureLine();
    if (!detail2.empty()) res.reason += " [" + detail2 + "]";
    return res;
  }
  g_tunnel.engine = engine;
  g_tunnel.up = true;
  res.kind = TunnelStartKind::kOk;
  return res;
}

}  // namespace

TunnelStartResult StartTunnel(int port, int session, bool tcpOnly,
                               bool socksStrict) {
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

  res = BringUpZeptun(BuildZeptunToml(port, tcpOnly, socksStrict));
  if (res.kind == TunnelStartKind::kOk) {
    g_tunnel.port = port;
    g_tunnel.tcpOnly = tcpOnly;
    g_tunnel.session = session;
    if (session > g_tunnel.liveSession) g_tunnel.liveSession = session;
    // v4.40 — the system-proxy companion (owner round 14): while the
    // whole-device tunnel is up, the OS proxy points at the same local
    // SOCKS5 listener so proxy-only apps (browsers first) ride the tunnel
    // too. Honest failure: the outcome lands in the captured core log,
    // the tunnel itself is unaffected.
    const std::string proxy_err = SetSystemProxy(port);
    if (!proxy_err.empty()) {
      fprintf(stderr,
              "system-proxy: NOT set (err=\"%s\") — the tunnel still "
              "works; proxy-aware apps may not follow it\n",
              proxy_err.c_str());
    } else {
      fprintf(stderr,
              "system-proxy: OS proxy -> socks5://127.0.0.1:%d "
              "(restored on stop)\n",
              port);
    }
  }
  return res;
}

#ifndef _WIN32
// ---- v4.37: the async helper bring-up (Linux normal-user tunnel mode) ----

bool TunnelPrivilegeViaHelper() { return geteuid() != 0; }

void SetTunnelEventSink(TunnelEventSink sink, void* ctx) {
  g_tunnel_sink = sink;
  g_tunnel_sink_ctx = ctx;
}

namespace {

// The full helper-path bring-up, run on a worker thread. Every failure
// surfaces through the event sink with the exact stage named — the walk's
// tunnelStartFailed screen shows it verbatim.
void HelperBringUpWorker(int port, int session, bool tcpOnly,
                         bool socksStrict) {
  const int stop_gen = g_async_stop_gen.load();

  // Straggler gate: a stop already superseded this start.
  if (session != 0 && session <= stop_gen) {
    EmitTunnelEvent(false, 0, session, "stale-start");
    g_async_bringing.store(false);
    return;
  }

  // A previous session's tunnel (if any) must be gone before we build the
  // next — no two TUNs, no two zeptun engines (the owner's lifecycle rules).
  {
    std::lock_guard<std::mutex> lock(g_tunnel_mutex);
    if (g_tunnel.up) {
      Zeptun* old = g_tunnel.engine;
      g_tunnel.engine = nullptr;
      g_tunnel.up = false;
      if (old) {
        if (g_zeptun.stop) g_zeptun.stop(old);
        if (g_zeptun.destroy) g_zeptun.destroy(old);
      }
    }
  }
  StopHelperPair();  // idempotent; reverts routes/rules of the old pair

  std::string err;
  if (!EnsureHelperInstalled(&err)) {
    EmitTunnelEvent(false, 0, session, "helper-install-failed: " + err);
    g_async_bringing.store(false);
    return;
  }
  if (!StartHelper(stop_gen, &err)) {
    EmitTunnelEvent(false, 0, session, "helper-start-failed: " + err);
    g_async_bringing.store(false);
    return;
  }

  std::string reply;
  int fd = -1;
  if (!HelperRequest("up", &reply, &fd) || fd < 0) {
    // The reply carries the helper's own diagnosis (TUNSETIFF EPERM,
    // netlink error, verification failure …) — strip the "ERR " prefix.
    const std::string why = reply.rfind("ERR ", 0) == 0
                                ? reply.substr(4)
                                : (reply.empty() ? "no reply" : reply);
    EmitTunnelEvent(false, 0, session,
                    "tunnel-privileged-setup-failed: " + why);
    g_async_bringing.store(false);
    return;
  }

  // zeptun adopts the pre-created, VERIFIED TUN fd (configure=false,
  // auto_route=false — the helper already did the privileged half).
  bool ok = false;
  std::string fail_reason;
  {
    std::lock_guard<std::mutex> lock(g_tunnel_mutex);
    if (session != 0 && session <= g_tunnel.stopGeneration) {
      fail_reason = "stale-start";  // a stop landed while the dialog was up
    } else {
      const TunnelStartResult res =
          BringUpZeptun(BuildZeptunTomlFd(port, tcpOnly, fd, socksStrict));
      if (res.kind == TunnelStartKind::kOk) {
        g_tunnel.port = port;
        g_tunnel.tcpOnly = tcpOnly;
        g_tunnel.session = session;
        if (session > g_tunnel.liveSession) g_tunnel.liveSession = session;
        ok = true;
      } else {
        fail_reason = res.reason;
      }
    }
  }
  if (ok) {
    {
      std::lock_guard<std::mutex> lock(g_helper_mutex);
      g_helper.tun_fd = fd;  // ours to close on stop (zeptun .fd never owns)
    }
    HelperLog(
        HelperLogLine("tunnel: up (helper fd adopted, zeptun running)"));
    // v4.40 — the system-proxy companion on the helper path too (the
    // same round-14 decree; see StartTunnel).
    {
      const std::string proxy_err = SetSystemProxy(port);
      if (!proxy_err.empty()) {
        HelperLog(HelperLogLine("system-proxy: NOT set (" + proxy_err +
                                ") — the tunnel still works"));
      } else {
        HelperLog(HelperLogLine(
            "system-proxy: OS proxy -> socks5://127.0.0.1:" +
            std::to_string(port) + " (restored on stop)"));
      }
    }
    EmitTunnelEvent(true, port, session, "");
  } else {
    close(fd);
    HelperLog(HelperLogLine("tunnel: zeptun failed on the helper fd — " +
                            fail_reason));
    EmitTunnelEvent(false, 0, session, fail_reason);
    StopHelperPair();
  }
  g_async_bringing.store(false);
}

}  // namespace

void StartTunnelAsync(int port, int session, bool tcpOnly, bool socksStrict) {
  if (g_async_bringing.exchange(true)) {
    // A bring-up is already in flight (the walk serializes starts, but a
    // straggler start must never stack a second helper): report it stale.
    EmitTunnelEvent(false, 0, session, "stale-start");
    return;
  }
  std::thread(HelperBringUpWorker, port, session, tcpOnly, socksStrict)
      .detach();
}

TunnelPathProbe VerifyTunnelPath() {
  TunnelPathProbe out{false, false, 0, ""};
  // Only meaningful when the helper owns the tunnel. In direct/root mode the
  // app's own uid is excluded from the TUN, so an in-process probe could
  // never traverse it — the local SOCKS probe remains the gate there
  // (documented in LINUX_RUNTIME_AND_TUNNEL_FIX_REPORT.md).
  {
    std::lock_guard<std::mutex> lock(g_helper_mutex);
    if (g_helper.sock < 0 || g_helper.tun_fd < 0) {
      out.detail = "not attempted: the tunnel is not helper-backed";
      return out;
    }
  }
  std::string reply;
  if (!HelperRequest("probe", &reply, nullptr)) {
    out.detail = reply.empty() ? "the helper did not answer the probe"
                               : reply.substr(reply.rfind("ERR ", 0) == 0
                                                  ? 4
                                                  : 0);
    return out;
  }
  out.attempted = true;
  if (reply.rfind("OK ", 0) == 0) {
    const size_t sp = reply.find(' ', 3);
    out.elapsedMs = strtoll(reply.c_str() + 3, nullptr, 10);
    out.verified = true;
    out.detail = sp == std::string::npos ? reply
                                         : reply.substr(sp + 1);
    // one line only — the detail is for a UI reason line
    const size_t nl = out.detail.find('\n');
    if (nl != std::string::npos) out.detail.resize(nl);
  } else {
    out.detail = reply.rfind("ERR ", 0) == 0 ? reply.substr(4) : reply;
    const size_t nl = out.detail.find('\n');
    if (nl != std::string::npos) out.detail.resize(nl);
  }
  HelperLog(HelperLogLine("verify: " + reply));
  return out;
}

#else  // _WIN32

bool TunnelPrivilegeViaHelper() { return false; }
void SetTunnelEventSink(TunnelEventSink, void*) {}
void StartTunnelAsync(int, int, bool, bool) {}
TunnelPathProbe VerifyTunnelPath() {
  return TunnelPathProbe{false, false, 0,
                         "not attempted: helper is Linux-only"};
}

#endif  // !_WIN32

int StopTunnel() {
  std::lock_guard<std::mutex> lock(g_tunnel_mutex);
  if (g_tunnel.liveSession > g_tunnel.stopGeneration) {
    g_tunnel.stopGeneration = g_tunnel.liveSession;
  }
#ifndef _WIN32
  g_async_stop_gen.store(g_tunnel.stopGeneration);  // cancel an in-flight bring-up
#endif
  Zeptun* engine = g_tunnel.engine;
  g_tunnel.engine = nullptr;
  g_tunnel.up = false;
  if (engine) {
    if (g_zeptun.stop) g_zeptun.stop(engine);  // idempotent by bridge design
    if (g_zeptun.destroy) g_zeptun.destroy(engine);
  }
#ifndef _WIN32
  // The helper pair goes down too (routes/rules/resolved reverted; the
  // helper exits on the socket close — EOF is its teardown trigger).
  StopHelperPair();
  HelperLog(HelperLogLine("tunnel: down (user stop)"));
#endif
  // v4.40 — the system-proxy companion goes down with the tunnel: the
  // user's own pre-session OS proxy state is restored (the backup file was
  // written at set time; SystemProxyHygiene covers a crashed session).
  {
    const std::string proxy_err = ClearSystemProxy();
    if (!proxy_err.empty()) {
      fprintf(stderr, "system-proxy: restore failed (err=\"%s\")\n",
              proxy_err.c_str());
    }
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

#ifndef _WIN32
// ---- v4.39: the Linux root-from-start model + the system integration ----

namespace {

bool WriteFileIfChanged(const std::string& path, const std::string& data) {
  bool same = false;
  FILE* f = FileOpen(path, "rb");
  if (f != nullptr) {
    std::string existing(data.size(), '\0');
    const size_t got = fread(&existing[0], 1, existing.size(), f);
    existing.resize(got);
    same = got == data.size() && existing == data;
    fclose(f);
  }
  if (same) return true;  // idempotent: no churn on every root launch
  f = FileOpen(path, "wb");
  if (f == nullptr) return false;
  const size_t wrote = fwrite(data.data(), 1, data.size(), f);
  fclose(f);
  return wrote == data.size();
}

bool ReadAllBytes(const std::string& path, std::string* out) {
  FILE* f = FileOpen(path, "rb");
  if (f == nullptr) return false;
  char buf[8192];
  for (;;) {
    const size_t n = fread(buf, 1, sizeof(buf), f);
    if (n == 0) break;
    out->append(buf, n);
  }
  fclose(f);
  return !out->empty();
}

}  // namespace

bool ElevateAtStartup(int* exit_code) {
  *exit_code = 0;
  if (geteuid() == 0) return false;  // already root (sudo / the menu entry)
  // The loop guard doubles as the user's escape hatch: the elevated side
  // sets it (so the root instance never re-prompts), and anyone can plant
  // it to force the unprivileged mode on purpose.
  if (getenv("AETHONE_ELEVATION_ATTEMPT") != nullptr) return false;
  // Headless / CI launches (the desktop-smoke Xvfb boot) must never sit on
  // a polkit prompt: only ask when a real session marked the environment.
  // CI=true covers every hosted-runner environment explicitly — the smoke
  // gate stays deterministic even if an image ever sets XDG_CURRENT_DESKTOP.
  if (getenv("CI") != nullptr) return false;
  const char* const desktop = getenv("XDG_CURRENT_DESKTOP");
  const char* const session = getenv("DESKTOP_SESSION");
  const bool interactive = (desktop != nullptr && *desktop != 0) ||
                           (session != nullptr && *session != 0);
  if (!interactive) return false;
  const char* pkexec =
      access("/usr/bin/pkexec", X_OK) == 0
          ? "/usr/bin/pkexec"
          : (access("/bin/pkexec", X_OK) == 0 ? "/bin/pkexec" : nullptr);
  if (pkexec == nullptr) return false;  // no polkit — the v4.37 helper path stays
  const char* const env_exe =
      access("/usr/bin/env", X_OK) == 0 ? "/usr/bin/env" : "/bin/env";
  if (access(env_exe, X_OK) != 0) return false;

  // The session plumbing the elevated instance needs to reach the user's
  // display. Everything else (HOME, XDG_DATA_HOME) deliberately re-roots:
  // the root instance's app data lives under /root, never inside the
  // invoking user's directories — root-owned files there would break the
  // unprivileged fallback's own writes.
  std::vector<std::string> pass;
  const char* const kSessionVars[] = {
      "DISPLAY",         "WAYLAND_DISPLAY", "XAUTHORITY",
      "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP",
      "DESKTOP_SESSION", "DBUS_SESSION_BUS_ADDRESS", "LANG",
  };
  for (const char* name : kSessionVars) {
    const char* const value = getenv(name);
    if (value != nullptr && *value != 0) {
      pass.push_back(std::string(name) + "=" + value);
    }
  }
  pass.push_back("AETHONE_ELEVATION_ATTEMPT=1");

  const std::string self = ExePath();
  if (self.empty() || access(self.c_str(), X_OK) != 0) return false;

  std::vector<char*> argv;
  argv.push_back(const_cast<char*>("pkexec"));
  argv.push_back(const_cast<char*>(env_exe));
  for (const std::string& kv : pass) {
    argv.push_back(const_cast<char*>(kv.c_str()));
  }
  argv.push_back(const_cast<char*>(self.c_str()));
  argv.push_back(nullptr);

  pid_t pid = -1;
  if (posix_spawn(&pid, pkexec, nullptr, nullptr, argv.data(), environ) != 0) {
    return false;
  }
  // The user may sit on the password prompt for a while (the walk's Linux
  // permission-budget twin); the cap cancels instead of hanging forever.
  const int kElevateWaitMs = 300000;
  int status = 0;
  bool ran = false;
  for (int waited = 0; waited < kElevateWaitMs; waited += 100) {
    if (waitpid(pid, &status, WNOHANG) == pid) {
      ran = true;
      break;
    }
    usleep(100 * 1000);
  }
  if (!ran) {
    kill(pid, SIGTERM);
    waitpid(pid, &status, 0);
    return false;
  }
  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    *exit_code = 0;  // the elevated session ran to completion
    return true;
  }
  // Declined (126) / no agent (127) / the root instance exited nonzero:
  // fall through in THIS process as the unprivileged app — the v4.37
  // helper path remains available for tunnels.
  return false;
}

void EnsureDesktopIntegration() {
  if (geteuid() != 0) return;  // only the root instance writes /usr/share
  const DesktopPaths& p = Paths();
  const std::string icon_src = p.exeDir + "/aethone-icon.png";
  const std::string hicolor_dir = "/usr/share/icons/hicolor/256x256/apps";
  const std::string hicolor_icon =
      hicolor_dir + "/com.chakcaad.aethone.png";
  const std::string desktop_path =
      "/usr/share/applications/com.chakcaad.aethone.desktop";

  // 1. the hicolor app icon — the owner's mark on white (the menu/grid
  //    face; the tray keeps the transparent mark, shipped as the bundle's
  //    aethone-tray.png).
  bool icon_ok = false;
  std::string icon_bytes;
  if (ReadAllBytes(icon_src, &icon_bytes)) {
    MkDirAll(hicolor_dir);
    icon_ok = WriteFileIfChanged(hicolor_icon, icon_bytes);
  }

  // 2. the menu entry — Exec always points at THIS bundle's current
  //    location, so a moved bundle self-heals on its next root launch.
  const std::string entry =
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=AETHONE\n"
      "Exec=" + p.exeDir + "/aethone\n"
      "Icon=com.chakcaad.aethone\n"
      "Terminal=false\n"
      "Categories=Network;\n"
      "StartupWMClass=com.chakcaad.aethone\n";
  MkDirAll("/usr/share/applications");
  const bool entry_ok = WriteFileIfChanged(desktop_path, entry);

  if (!icon_ok || !entry_ok) {
    // Best effort by decree: a read-only /usr (immutable ostree) or a
    // missing bundle icon must never block the launch — the outcome lands
    // in the captured core log for the settings page.
    fprintf(stderr,
            "desktop-integration: icon_ok=%d entry_ok=%d (best effort; "
            "the app runs regardless)\n",
            icon_ok ? 1 : 0, entry_ok ? 1 : 0);
  }
}

#else  // _WIN32

bool ElevateAtStartup(int*) { return false; }  // the exe manifest already carries requireAdministrator
void EnsureDesktopIntegration() {}             // Windows uses embedded resources

#endif  // !_WIN32

// ---------------------------------------------------------------------------
// v4.40 — the SYSTEM-PROXY COMPANION of the tunnel mode (owner round 14:
// «وقتی حالت تونل فعاله ... علاوه بر این که تونل فعال میشه پروکسی سیستم هم
// ست بشه تا مرورگر ها و برنامه هایی که پروکسی فقط ساپورت میکنن تونل بشن»).
//
// While the whole-device tunnel is up, the core's local SOCKS5 listener is
// ALREADY reachable on 127.0.0.1:<port> — pointing the OS proxy at it routes
// every proxy-aware application (browsers first) through the very same
// tunnel, so proxy-only apps no longer leak around the TUN.
//
//  * SetSystemProxy(port): saves the OS's previous proxy state to
//    <filesDir>/system-proxy-backup.txt, then points the OS at
//    socks5://127.0.0.1:<port>.
//  * ClearSystemProxy(): restores the saved state (or disables the proxy
//    when nothing was saved).
//  * SystemProxyHygiene(): called at EVERY process start — if a previous
//    session crashed while the proxy was set (the backup file survived),
//    the state is restored right there, before the UI even comes up.
//
// Honest-failure discipline: every function returns an error string (empty
// = success) which the glue layer logs into the core log; a desktop
// without a supported proxy backend (no gsettings, exotic DE) keeps the
// tunnel — only the companion is missing.
// ---------------------------------------------------------------------------
namespace {

std::string ProxyBackupPath() { return Paths().filesDir + "/system-proxy-backup.txt"; }

bool ProxyFileRead(const std::string& path, std::string* out) {
  FILE* f = FileOpen(path, "rb");
  if (f == nullptr) return false;
  std::string data;
  char buf[4096];
  size_t got;
  while ((got = fread(buf, 1, sizeof(buf), f)) > 0) data.append(buf, got);
  fclose(f);
  *out = data;
  return true;
}

bool ProxyFileWrite(const std::string& path, const std::string& data) {
  FILE* f = FileOpen(path, "wb");
  if (f == nullptr) return false;
  const size_t wrote = fwrite(data.data(), 1, data.size(), f);
  fclose(f);
  return wrote == data.size();
}

#ifdef _WIN32

// The WinInet proxy (the setting Chrome/Edge/FollowSystem read):
// HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings.
constexpr wchar_t kInetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

bool RegReadString(HKEY key, const wchar_t* name, std::string* out) {
  DWORD type = 0, size = 0;
  if (RegQueryValueExW(key, name, nullptr, &type, nullptr, &size) !=
          ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ) || size == 0 || size > 8192) {
    return false;
  }
  std::wstring wide(size / sizeof(wchar_t), L'\0');
  if (RegQueryValueExW(key, name, nullptr, &type,
                       reinterpret_cast<LPBYTE>(&wide[0]), &size) !=
      ERROR_SUCCESS) {
    return false;
  }
  wide.resize(size / sizeof(wchar_t));
  while (!wide.empty() && wide.back() == L'\0') wide.pop_back();
  *out = WideToUtf8(wide.c_str(), wide.size());
  return true;
}

bool RegWriteString(HKEY key, const wchar_t* name, const std::string& value) {
  const std::wstring wide = Utf8ToWide(value);
  return RegSetValueExW(key, name, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(wide.c_str()),
                        static_cast<DWORD>((wide.size() + 1) *
                                           sizeof(wchar_t))) == ERROR_SUCCESS;
}

bool RegReadDword(HKEY key, const wchar_t* name, DWORD* out) {
  DWORD type = 0, size = sizeof(DWORD);
  return RegQueryValueExW(key, name, nullptr, &type,
                          reinterpret_cast<LPBYTE>(out), &size) ==
             ERROR_SUCCESS &&
         type == REG_DWORD;
}

bool RegWriteDword(HKEY key, const wchar_t* name, DWORD value) {
  return RegSetValueExW(key, name, 0, REG_DWORD,
                        reinterpret_cast<const BYTE*>(&value),
                        sizeof(value)) == ERROR_SUCCESS;
}

void NotifyWininetSettingsChanged() {
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

// The one-line backup format (parsed by the restore, written once):
//   enable=<0|1>\nserver=<raw ProxyServer value>\n
bool WinProxySaveBackup(HKEY key) {
  DWORD enable = 0;
  RegReadDword(key, L"ProxyEnable", &enable);
  std::string server;
  RegReadString(key, L"ProxyServer", &server);
  return ProxyFileWrite(ProxyBackupPath(),
                        "enable=" + std::to_string(enable) + "\n" +
                            "server=" + server + "\n");
}

bool WinProxyApplySaved(HKEY key, const std::string& saved) {
  DWORD enable = 0;
  std::string server;
  size_t e = saved.find("enable="), s = saved.find("server=");
  if (e == std::string::npos || s == std::string::npos) return false;
  enable = static_cast<DWORD>(atoi(saved.c_str() + e + 7));
  server = saved.substr(s + 7);
  while (!server.empty() && (server.back() == '\n' || server.back() == '\r'))
    server.pop_back();
  const bool ok = RegWriteDword(key, L"ProxyEnable", enable) &&
                  (server.empty() ? true
                                  : RegWriteString(key, L"ProxyServer", server));
  NotifyWininetSettingsChanged();
  return ok;
}

#else  // !_WIN32 — gsettings (GNOME family; other DEs log honestly)

// Runs `gsettings <args>` capturing stdout ("" on failure).
std::string GSettings(const std::string& args, bool* ok) {
  *ok = false;
  FILE* p = popen(("gsettings " + args + " 2>/dev/null").c_str(), "r");
  if (p == nullptr) return std::string();
  std::string out;
  char buf[512];
  while (fgets(buf, sizeof(buf), p) != nullptr) out += buf;
  const int rc = pclose(p);
  *ok = (rc == 0);
  return out;
}

std::string GSettingsTrim(const std::string& v) {
  std::string s = v;
  while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' '))
    s.pop_back();
  // strip the single quotes gsettings get wraps values in
  if (s.size() >= 2 && s.front() == '\'' && s.back() == '\'')
    s = s.substr(1, s.size() - 2);
  return s;
}

#endif  // !_WIN32

}  // namespace

std::string SetSystemProxy(int port) {
  if (port <= 0 || port > 65535) return "invalid port";
#ifdef _WIN32
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInetSettingsKey, 0, KEY_READ | KEY_WRITE,
                    &key) != ERROR_SUCCESS) {
    return "cannot open the Internet Settings registry key";
  }
  std::string err;
  do {
    if (!WinProxySaveBackup(key)) {
      err = "cannot write the proxy backup file";
      break;
    }
    // "socks=host:port" — the WinInet form every system-proxy follower reads;
    // browsers resolve it as the SOCKS endpoint for all protocols.
    if (!RegWriteDword(key, L"ProxyEnable", 1) ||
        !RegWriteString(key, L"ProxyServer",
                        "socks=127.0.0.1:" + std::to_string(port))) {
      err = "cannot write the proxy registry values";
      break;
    }
    NotifyWininetSettingsChanged();
  } while (false);
  RegCloseKey(key);
  return err;
#else
  bool ok = false;
  // Probe gsettings first (honest error when the desktop has none).
  GSettings("get org.gnome.system.proxy mode", &ok);
  if (!ok) return "gsettings not available on this desktop";
  std::string mode = GSettingsTrim(GSettings("get org.gnome.system.proxy mode", &ok));
  std::string host = GSettingsTrim(GSettings("get org.gnome.system.proxy.socks host", &ok));
  std::string port_s = GSettingsTrim(GSettings("get org.gnome.system.proxy.socks port", &ok));
  if (!ProxyFileWrite(ProxyBackupPath(),
                      "mode=" + mode + "\nsocks-host=" + host + "\nsocks-port=" +
                          port_s + "\n")) {
    return "cannot write the proxy backup file";
  }
  const std::string p = std::to_string(port);
  bool all = true;
  GSettings("set org.gnome.system.proxy mode 'manual'", &ok); all = all && ok;
  GSettings("set org.gnome.system.proxy.socks host '127.0.0.1'", &ok); all = all && ok;
  GSettings("set org.gnome.system.proxy.socks port " + p, &ok); all = all && ok;
  GSettings("set org.gnome.system.proxy ignore-hosts \"['localhost', '127.0.0.0/8', '::1']\"", &ok); all = all && ok;
  if (!all) return "one of the gsettings writes failed (see the core log)";
  return std::string();
#endif
}

std::string ClearSystemProxy() {
#ifdef _WIN32
  std::string saved;
  const bool had = ProxyFileRead(ProxyBackupPath(), &saved);
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kInetSettingsKey, 0, KEY_READ | KEY_WRITE,
                    &key) != ERROR_SUCCESS) {
    return "cannot open the Internet Settings registry key";
  }
  std::string err;
  if (had) {
    if (!WinProxyApplySaved(key, saved)) err = "cannot restore the saved proxy values";
  } else {
    if (!RegWriteDword(key, L"ProxyEnable", 0)) err = "cannot disable the system proxy";
    NotifyWininetSettingsChanged();
  }
  RegCloseKey(key);
  FileRemove(ProxyBackupPath());
  return err;
#else
  std::string saved;
  const bool had = ProxyFileRead(ProxyBackupPath(), &saved);
  bool ok = false;
  if (had) {
    // restore line-by-line: mode / socks-host / socks-port
    size_t pos = 0;
    while (pos < saved.size()) {
      size_t nl = saved.find('\n', pos);
      if (nl == std::string::npos) nl = saved.size();
      std::string line = saved.substr(pos, nl - pos);
      pos = nl + 1;
      if (line.rfind("mode=", 0) == 0) {
        GSettings("set org.gnome.system.proxy mode '" + line.substr(5) + "'", &ok);
      } else if (line.rfind("socks-host=", 0) == 0) {
        GSettings("set org.gnome.system.proxy.socks host '" + line.substr(11) + "'", &ok);
      } else if (line.rfind("socks-port=", 0) == 0) {
        GSettings("set org.gnome.system.proxy.socks port " + line.substr(11), &ok);
      }
    }
  } else {
    GSettings("set org.gnome.system.proxy mode 'none'", &ok);
    if (!ok) return "gsettings not available on this desktop";
  }
  FileRemove(ProxyBackupPath());
  return std::string();
#endif
}

std::string SystemProxyHygiene() {
  std::string saved;
  if (!ProxyFileRead(ProxyBackupPath(), &saved)) return std::string();
  // A backup file at boot = a previous session died with the proxy set —
  // restore the user's own state right now.
  const std::string err = ClearSystemProxy();
  fprintf(stderr,
          "system-proxy: restored the pre-session OS proxy state at startup "
          "(a previous session left it set; err=\"%s\")\n",
          err.c_str());
  return err;
}

// ---- v4.40: the login auto-start (general settings, desktop only) ---------

#ifdef _WIN32

bool AutoStartSet(bool enabled) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_READ | KEY_WRITE,
                    &key) != ERROR_SUCCESS) {
    return false;
  }
  bool ok;
  if (enabled) {
    char self[MAX_PATH] = {};
    GetModuleFileNameA(nullptr, self, MAX_PATH);
    ok = RegWriteString(key, L"AETHONE", self);
  } else {
    ok = RegDeleteValueW(key, L"AETHONE") == ERROR_SUCCESS ||
         GetLastError() == ERROR_FILE_NOT_FOUND;
  }
  RegCloseKey(key);
  return ok;
}

bool AutoStartIsEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  std::string v;
  const bool present = RegReadString(key, L"AETHONE", &v);
  RegCloseKey(key);
  return present;
}

std::string SetAutoStart(bool enabled) {
  return AutoStartSet(enabled) ? std::string()
                               : "cannot write the HKCU Run entry";
}

#else  // Linux: the freedesktop autostart .desktop

std::string AutoStartDesktopPath() {
  // v4.40 — the app runs ELEVATED on Linux (the v4.39 root-from-start
  // model), so $HOME is root's — the login autostart must land in the
  // DESKTOP session user's config. Polkit hands the original user over in
  // SUDO_USER; without it we fall back to $HOME (a normal-user run).
  const char* sudo_user = getenv("SUDO_USER");
  std::string base;
  if (sudo_user != nullptr && sudo_user[0] != '\0') {
    const passwd* pw = getpwnam(sudo_user);
    if (pw != nullptr && pw->pw_dir != nullptr) {
      base = std::string(pw->pw_dir) + "/.config";
    }
  }
  if (base.empty()) {
    const char* config = getenv("XDG_CONFIG_HOME");
    base = (config != nullptr && config[0] != '\0')
               ? std::string(config)
               : std::string(getenv("HOME") ? getenv("HOME") : "/root") +
                     "/.config";
  }
  return base + "/autostart/aethone.desktop";
}

bool AutoStartIsEnabled() {
  std::string data;
  return ProxyFileRead(AutoStartDesktopPath(), &data);
}

std::string SetAutoStart(bool enabled) {
  const std::string path = AutoStartDesktopPath();
  if (!enabled) {
    FileRemove(path);
    return std::string();
  }
  const DesktopPaths& p = Paths();
  const std::string entry =
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=AETHONE\n"
      "Exec=" + p.exeDir + "/aethone\n"
      "Icon=com.chakcaad.aethone\n"
      "Terminal=false\n"
      "X-GNOME-Autostart-enabled=true\n";
  std::string dir = path;
  const size_t slash = dir.rfind('/');
  if (slash != std::string::npos) {
    dir.resize(slash);
    MkDirAll(dir);
  }
  return ProxyFileWrite(path, entry) ? std::string()
                                     : "cannot write " + path;
}

#endif  // !_WIN32

}  // namespace aethone
