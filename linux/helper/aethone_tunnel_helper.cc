// aethone_tunnel_helper.cc — the Linux privilege helper (v4.37 runtime round).
//
// WHY THIS EXISTS (the root cause it fixes)
// -----------------------------------------
// The desktop tunnel path embeds zeptun in-process (libzeptun.so). Creating
// the TUN device (ioctl TUNSETIFF), configuring its link (netlink
// RTM_NEWLINK/RTM_NEWADDR) and installing the policy routes/rules
// (RTM_NEWROUTE/RTM_NEWRULE) all require CAP_NET_ADMIN. As a normal user the
// walk died with `zeptun-start-failed:rc=-3 (permission denied)`; the only
// workaround was running the WHOLE app under sudo, which also moved the WARP
// identity store under /root/.local/share — both wrong.
//
// This helper is the fix required by the owner's decree: the GUI keeps
// running as the normal user; ONLY the essential network operations run
// elevated, requested per-connection through Polkit (pkexec). The helper:
//
//   1. is installed system-wide on first tunnel connect
//      (/usr/libexec/aethone-tunnel-helper + the Polkit action file
//      com.chakcaad.aethone.tunnel-helper.policy), via ONE pkexec invocation
//      of /bin/sh -c 'install ... && install ...' (pkexec refuses to execute
//      binaries that live in user-writable directories — the app bundle — so
//      the copy has to be done by a root-owned system tool);
//   2. is then started per connection: pkexec aethone-tunnel-helper --serve
//      <socket>. One Polkit prompt per connect (auth_admin_keep in the
//      shipped policy keeps repeats within the keep window passwordless);
//   3. serves EXACTLY ONE client — the app — over a Unix socket in the
//      user's XDG_RUNTIME_DIR. The client is authenticated with
//      SO_PEERCRED: the connecting uid must be non-root and equal to the
//      owner of the socket's directory (pkexec's user), so no other local
//      user can talk to it;
//   4. on `up`: opens /dev/net/tun (IFF_TUN|IFF_NO_PI, name aethone0),
//      mirrors zeptun's own desktop bring-up EXACTLY (route/linux.zig at the
//      frozen pin 08a1ab05: MTU 1500, txqueuelen 4096, address
//      172.19.0.1/30, rp_filter relaxed to 2, default route → table 2022,
//      policy rules 9000/9004/9005/9009 with the caller's uid excluded and
//      fwmark 0x2022), VERIFIES the result (fail-closed: rules + route +
//      interface read back), hands the TUN fd to the app with SCM_RIGHTS and
//      closes its own copy — the unprivileged process owns the data plane
//      from here on, exactly like Android's VpnService model;
//   5. on `down` or EOF (app exit/crash): removes the rules, the table-2022
//      route, the resolved DNS delegation and the link itself. A crashed
//      pair leaves at most stale rules that fall through to the main table
//      (benign), and every `up` first clears 9000..9009 for both families —
//      self-healing;
//   6. on `probe`: performs a REAL end-to-end verification THROUGH the
//      tunnel (resolve www.cloudflare.com via the system resolver → the
//      tunnel's fake-IP DNS, connect :80, GET /cdn-cgi/trace, read bytes).
//      The helper runs as uid 0, which is NOT excluded by the uid rule —
//      its traffic genuinely traverses TUN → zeptun → SOCKS5 → the Aether
//      core. The app only reports Connected after this probe passes
//      (the owner's requirement D).
//
// The command set is closed: up / down / probe / bye. No arbitrary commands,
// no file paths, no arguments beyond the socket path — "limited to the
// essential operations" by construction.
//
// Everything below deliberately mirrors the vendored zeptun sources
// (native/zeptun at pin 08a1ab05):
//   * route/linux.zig  — netlink constants, message layout, installAutoRoute
//                        order, teardown, txQueueLen math, rp_filter relax
//   * route/resolved.zig — the resolvectl dns/domain/default-route dance
//   * device/linux.zig — TUNSETIFF with IFF_TUN|IFF_NO_PI (no vnet_hdr: the
//                        .fd engine path reads raw IP packets)
//   * config.zig       — the desktop constants (table 2022, priority 9000,
//                        fwmark 0x2022/0xffffffff, DNS host(2) 172.19.0.2)
//
// Build: plain C++17, no external dependencies, -march=x86-64 floor inherited
// from linux/CMakeLists.txt (the v4.36n x86-64-v1 ISA discipline).

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <functional>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <string>

// ---------------------------------------------------------------------------
// The mirrored constants (zeptun pin 08a1ab05 — see the header comment).
// ---------------------------------------------------------------------------
static const char kTunName[] = "aethone0";
static const char kTunPath[] = "/dev/net/tun";
static const uint32_t kTunMtu = 1500;
// engine.zig txQueueLen(): caps.vnet_hdr == false (the .fd path) →
// clamp((8<<20)/mtu, 1000, 4096) = 4096 for mtu 1500.
static const uint32_t kTunTxQueueLen = 4096;
static const uint32_t kTable = 2022;          // config.zig RouteConfig.table
static const uint32_t kRuleBase = 9000;       // rule_priority
static const uint32_t kRuleSpan = 10;         // route/linux.zig rule_span
static const uint32_t kFwmark = 0x2022;       // fwmark (non-Android)
static const uint32_t kFwmask = 0xffffffffu;  // fwmark_mask (non-Android)
static const uint32_t kTunAddrHost = 0xac130001u;  // 172.19.0.1 (BE in attrs)
static const int kTunPrefix = 30;
static const uint32_t kDnsAddrHost = 0xac130002u;  // 172.19.0.2 = host(2)
static const char kProbeHost[] = "www.cloudflare.com";
static const char kProbePath[] = "/cdn-cgi/trace";

// The Polkit action file, embedded — `--self-install` writes it verbatim to
// /usr/share/polkit-1/actions/. MUST stay in sync with the shipped copy at
// linux/packaging/com.chakcaad.aethone.tunnel-helper.policy (the bundle
// ships it for inspection; the embedded copy is what actually installs).
static const char kPolicyXml[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE policyconfig PUBLIC\n"
    " \"-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN\"\n"
    " \"http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd\">\n"
    "<policyconfig>\n"
    "  <vendor>CHAKCAAD</vendor>\n"
    "  <vendor_url>https://github.com/CHAKCAAD/AETHONE</vendor_url>\n"
    "  <action id=\"com.chakcaad.aethone.tunnel-helper\">\n"
    "    <description>Set up the AETHONE VPN tunnel</description>\n"
    "    <description xml:lang=\"fa\">راه‌اندازی تونل AETHONE</description>\n"
    "    <message>Authentication is required to create the AETHONE VPN tunnel device and its routes. Only these network operations run with administrator privileges; the app itself keeps running as your user.</message>\n"
    "    <message xml:lang=\"fa\">برای ایجاد دستگاه تونل و مسیرهای AETHONE احراز هویت لازم است. تنها همین عملیات‌های شبکه با دسترسی مدیریتی اجرا می‌شوند؛ خود برنامه با کاربر شما اجرا می‌شود.</message>\n"
    "    <defaults>\n"
    "      <allow_any>auth_admin_keep</allow_any>\n"
    "      <allow_inactive>auth_admin_keep</allow_inactive>\n"
    "      <allow_active>auth_admin_keep</allow_active>\n"
    "    </defaults>\n"
    "    <annotate key=\"org.freedesktop.policykit.exec.path\">/usr/libexec/aethone-tunnel-helper</annotate>\n"
    "    <annotate key=\"org.freedesktop.policykit.exec.allow_undefined\">no</annotate>\n"
    "  </action>\n"
    "</policyconfig>\n";

static const char kHelperInstallPath[] = "/usr/libexec/aethone-tunnel-helper";
static const char kHelperPolicyInstallPath[] =
    "/usr/share/polkit-1/actions/com.chakcaad.aethone.tunnel-helper.policy";

// netlink (linux/rtnetlink.h constants, mirrored from route/linux.zig)
static const uint16_t NLMSG_ERROR = 2;
static const uint16_t NLMSG_DONE = 3;
static const uint16_t NLM_F_REQUEST = 0x01;
static const uint16_t NLM_F_ACK = 0x04;
static const uint16_t NLM_F_CREATE = 0x400;
static const uint16_t NLM_F_EXCL = 0x200;
static const uint16_t NLM_F_REPLACE = 0x100;
static const uint16_t NLM_F_DUMP = 0x300;
static const uint16_t RTM_NEWLINK = 16, RTM_DELLINK = 17, RTM_GETLINK = 18,
                       RTM_NEWADDR = 20, RTM_DELADDR = 21, RTM_GETADDR = 22,
                       RTM_NEWROUTE = 24, RTM_DELROUTE = 25,
                       RTM_GETROUTE = 26, RTM_NEWRULE = 32, RTM_DELRULE = 33,
                       RTM_GETRULE = 34;
static const uint16_t IFLA_IFNAME = 3, IFLA_MTU = 4, IFLA_TXQLEN = 13;
static const uint16_t IFA_ADDRESS = 1, IFA_LOCAL = 2;
static const uint16_t RTA_DST = 1, RTA_OIF = 4, RTA_TABLE = 15;
static const uint16_t FRA_DST = 1, FRA_GOTO = 4, FRA_PRIORITY = 6,
                       FRA_FWMARK = 10, FRA_TABLE = 15, FRA_FWMASK = 16,
                       FRA_SUPPRESS_PREFIXLEN = 14, FRA_UID_RANGE = 20;
static const uint8_t FR_ACT_TO_TBL = 1, FR_ACT_GOTO = 2, FR_ACT_NOP = 3;
static const uint32_t FIB_RULE_INVERT = 0x02;
static const uint32_t RT_TABLE_MAIN = 254, RT_TABLE_UNSPEC = 0;
static const uint8_t RTPROT_STATIC = 4, RT_SCOPE_LINK = 253,
                     RT_SCOPE_UNIVERSE = 0, RTN_UNICAST = 1;
static const int NETLINK_ROUTE_PROTO = 0;  // NETLINK_ROUTE (linux/netlink.h)
struct SockaddrNl {
  sa_family_t nl_family;
  uint16_t nl_pad;
  uint32_t nl_pid;
  uint32_t nl_groups;
};
static const uint32_t IFF_UP_FLAG = 0x1;
// _IOW('T', 202, int) — TUNSETIFF (the value the pinned if_tun.zig computes).
static const unsigned long TUNSETIFF_IOC = 0x400454caUL;
static const unsigned short IFF_TUN_FLAG = 0x0001, IFF_NO_PI_FLAG = 0x1000;

// ---------------------------------------------------------------------------
// Logging — stderr with timestamps. The app redirects this stream into
// <filesDir>/logs/helper-log.txt (separable from the core log, per the
// owner's logging decree).
// ---------------------------------------------------------------------------
static void Log(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
static void Log(const char* fmt, ...) {
  char stamp[32];
  const time_t now = time(nullptr);
  struct tm tmv;
  localtime_r(&now, &tmv);
  strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
  fprintf(stderr, "[%s] aethone-tunnel-helper: ", stamp);
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
  fflush(stderr);
}

static std::string ErrnoStr(int e) { return strerror(e ? e : errno); }

// ---------------------------------------------------------------------------
// The netlink builder — byte-for-byte the layout of zeptun's route/linux.zig
// Builder (begin/body/attr/finish), so the emitted messages are exactly what
// the pinned engine would have sent had it run privileged.
// ---------------------------------------------------------------------------
struct NlMsgHdr {
  uint32_t len;
  uint16_t kind;
  uint16_t flags;
  uint32_t seq;
  uint32_t pid;
};
struct IfInfoMsg {  // ifinfomsg
  uint8_t family;
  uint8_t pad;
  uint16_t kind;
  int32_t index;
  uint32_t flags;
  uint32_t change;
};
struct IfAddrMsg {  // ifaddrmsg
  uint8_t family;
  uint8_t prefixlen;
  uint8_t flags;
  uint8_t scope;
  uint32_t index;
};
struct RtMsg {  // rtmsg
  uint8_t family;
  uint8_t dst_len;
  uint8_t src_len;
  uint8_t tos;
  uint8_t table;
  uint8_t protocol;
  uint8_t scope;
  uint8_t kind;
  uint32_t flags;
};
struct FibRuleHdr {  // fib_rule_hdr
  uint8_t family;
  uint8_t dst_len;
  uint8_t src_len;
  uint8_t tos;
  uint8_t table;
  uint8_t res1;
  uint8_t res2;
  uint8_t action;
  uint32_t flags;
};

class Builder {
 public:
  Builder() { memset(buf_, 0, sizeof(buf_)); }
  void Begin(uint16_t kind, uint16_t flags, uint32_t seq) {
    len_ = sizeof(NlMsgHdr);
    NlMsgHdr h;
    memset(&h, 0, sizeof(h));
    h.kind = kind;
    h.flags = flags | NLM_F_REQUEST | NLM_F_ACK;
    h.seq = seq;
    memcpy(buf_, &h, sizeof(h));
  }
  void Body(const void* data, size_t n) {
    memcpy(buf_ + len_, data, n);
    len_ = (len_ + n + 3) & ~static_cast<size_t>(3);
  }
  template <typename T>
  void Body(const T& v) {
    Body(&v, sizeof(v));
  }
  void Attr(uint16_t kind, const void* data, size_t n) {
    const size_t total = 4 + n;
    const uint16_t len16 = static_cast<uint16_t>(total);
    const uint16_t kind16 = kind;
    memcpy(buf_ + len_, &len16, 2);
    memcpy(buf_ + len_ + 2, &kind16, 2);
    if (n) memcpy(buf_ + len_ + 4, data, n);
    len_ = (len_ + total + 3) & ~static_cast<size_t>(3);
  }
  void AttrU32(uint16_t kind, uint32_t v) { Attr(kind, &v, 4); }

  const uint8_t* Finish() {
    const uint32_t l = static_cast<uint32_t>(len_);
    memcpy(buf_, &l, 4);
    return buf_;
  }
  size_t size() const { return len_; }

 private:
  uint8_t buf_[1024] __attribute__((aligned(4)));
  size_t len_ = 0;
};

class Netlink;

// ---------------------------------------------------------------------------
// Netlink socket: open/bind/transact-with-ACK (the transact of
// route/linux.zig, error classes included) + the two dump helpers the
// verification pass needs.
// ---------------------------------------------------------------------------
class Netlink {
 public:
  ~Netlink() {
    if (fd_ >= 0) close(fd_);
  }
  bool Open() {
    fd_ = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE_PROTO);
    if (fd_ < 0) {
      err_ = "socket(AF_NETLINK): " + ErrnoStr(0);
      return false;
    }
    SockaddrNl sa;
    memset(&sa, 0, sizeof(sa));
    sa.nl_family = AF_NETLINK;
    if (bind(fd_, reinterpret_cast<sockaddr*>(&sa), sizeof(sa)) < 0) {
      err_ = "bind(AF_NETLINK): " + ErrnoStr(0);
      return false;
    }
    return true;
  }
  const std::string& error() const { return err_; }
  int last_errno() const { return err_errno_; }

  // Sends `msg` (Builder layout, seq patched) and waits for its ACK.
  bool Transact(const uint8_t* msg, size_t len) {
    const uint32_t seq = seq_++;
    uint8_t patched[1024];
    memcpy(patched, msg, len);
    memcpy(patched + 8, &seq, 4);  // NlMsgHdr.seq

    SockaddrNl dst;
    memset(&dst, 0, sizeof(dst));
    dst.nl_family = AF_NETLINK;
    if (sendto(fd_, patched, len, 0, reinterpret_cast<sockaddr*>(&dst),
               sizeof(dst)) < 0) {
      err_ = "netlink sendto: " + ErrnoStr(0);
      return false;
    }
    uint8_t rbuf[8192] __attribute__((aligned(4)));
    for (int attempts = 0; attempts < 64; ++attempts) {
      const ssize_t got = recv(fd_, rbuf, sizeof(rbuf), 0);
      if (got < 0) {
        if (errno == EAGAIN || errno == EINTR) continue;
        err_ = "netlink recv: " + ErrnoStr(0);
        return false;
      }
      size_t off = 0;
      const size_t total = static_cast<size_t>(got);
      while (off + sizeof(NlMsgHdr) <= total) {
        NlMsgHdr h;
        memcpy(&h, rbuf + off, sizeof(h));
        if (h.len < sizeof(NlMsgHdr) || off + h.len > total) {
          err_ = "netlink: truncated reply";
          return false;
        }
        if (h.kind == NLMSG_ERROR && h.seq == seq) {
          int32_t code = 0;
          memcpy(&code, rbuf + off + sizeof(NlMsgHdr), 4);
          if (code == 0) return true;
          err_errno_ = -code;
          err_ = "netlink error " + std::to_string(-code) + " (" +
                 ErrnoStr(-code) + ")";
          return false;
        }
        off += (h.len + 3) & ~3u;
      }
    }
    err_ = "netlink: no ACK";
    return false;
  }

  // Dumps RTM_GETRULE for family; calls back per fib_rule_hdr+attrs.
  bool DumpRules(uint8_t family,
                 const std::function<void(const FibRuleHdr&, const uint8_t*,
                                          size_t)>& on_rule);

  // Dumps RTM_GETROUTE for family, filtered to `table`; per rtmsg+attrs.
  bool DumpRoutes(uint8_t family, uint32_t table,
                  const std::function<void(const RtMsg&, const uint8_t*,
                                           size_t)>& on_route);

 private:
  bool SendDump(uint16_t kind, const void* hdr, size_t hdr_len);
  int fd_ = -1;
  uint32_t seq_ = 1;
  std::string err_;
  int err_errno_ = 0;
};

// ---------------------------------------------------------------------------
// The mirrored operations. Every function returns false with `err` set on
// failure; EEXIST tolerance mirrors the pinned code paths.
// ---------------------------------------------------------------------------
struct HelperError {
  std::string msg;
  int errno_class = 0;  // 0 = no errno mapping
};

static bool IfIndex(const char* name, uint32_t* out, HelperError* err) {
  const int s = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
  if (s < 0) {
    err->msg = "socket(SIOCGIFINDEX): " + ErrnoStr(0);
    return false;
  }
  struct NameIndex {
    char name[IFNAMSIZ];
    int index;
    char pad[20];
  } req;
  memset(&req, 0, sizeof(req));
  strncpy(req.name, name, IFNAMSIZ - 1);
  const int r = ioctl(s, SIOCGIFINDEX, &req);
  close(s);
  if (r < 0) {
    err->msg = std::string("SIOCGIFINDEX(") + name + "): " + ErrnoStr(0);
    err->errno_class = errno;
    return false;
  }
  *out = static_cast<uint32_t>(req.index);
  return true;
}

// device/linux.zig Tun.open(): /dev/net/tun + TUNSETIFF IFF_TUN|IFF_NO_PI.
static int OpenTun(HelperError* err) {
  const int fd = open(kTunPath, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    err->msg = std::string("open ") + kTunPath + ": " + ErrnoStr(0);
    err->errno_class = errno;
    return -1;
  }
  struct TunReq {
    char name[IFNAMSIZ];
    short flags;
    char pad[22];
  } req;
  memset(&req, 0, sizeof(req));
  strncpy(req.name, kTunName, IFNAMSIZ - 1);
  req.flags = static_cast<short>(IFF_TUN_FLAG | IFF_NO_PI_FLAG);
  if (ioctl(fd, TUNSETIFF_IOC, &req) < 0) {
    err->msg = std::string("TUNSETIFF(") + kTunName + "): " + ErrnoStr(0);
    err->errno_class = errno;
    close(fd);
    return -1;
  }
  return fd;
}

// route/linux.zig relaxReversePathFilter(): 1 → 2, leave everything else.
static void RelaxRpFilter(const char* ifname) {
  char path[96];
  snprintf(path, sizeof(path), "/proc/sys/net/ipv4/conf/%s/rp_filter",
           ifname);
  const int fd = open(path, O_RDWR | O_CLOEXEC);
  if (fd < 0) return;
  char buf[8] = {0};
  const ssize_t n = read(fd, buf, sizeof(buf) - 1);
  if (n > 0) {
    const long value = strtol(buf, nullptr, 10);
    if (value == 1) (void)!pwrite(fd, "2", 1, 0);
  }
  close(fd);
}

// route/resolved.zig: the conditions + the three resolvectl calls.
static bool ResolvedOwned() {
  const int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) return false;
  sockaddr_in sa;
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_port = htons(53);
  sa.sin_addr.s_addr = htonl(0x7f000035u);  // 127.0.0.53
  int r = connect(fd, reinterpret_cast<sockaddr*>(&sa), sizeof(sa));
  if (r != 0 && (errno == EINPROGRESS || errno == EINTR)) {
    pollfd p{fd, POLLOUT, 0};
    if (poll(&p, 1, 100) <= 0) {
      close(fd);
      return false;
    }
    int soerr = 0;
    socklen_t slen = sizeof(soerr);
    r = (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen) == 0 &&
         soerr == 0)
            ? 0
            : -1;
  }
  close(fd);
  return r == 0;
}

static std::string ResolvedTool() {
  if (access("/run/systemd/resolve/resolv.conf", F_OK) != 0) return "";
  if (!ResolvedOwned()) return "";
  static const char* paths[] = {"/usr/bin/resolvectl", "/bin/resolvectl",
                                "/usr/sbin/resolvectl"};
  for (const char* p : paths) {
    if (access(p, X_OK) == 0) return p;
  }
  return "";
}

static bool RunTool(const std::string& exe, char* const argv[]) {
  const pid_t pid = fork();
  if (pid < 0) return false;
  if (pid == 0) {
    setenv("PATH", "/usr/sbin:/usr/bin:/sbin:/bin", 1);
    execv(exe.c_str(), argv);
    _exit(127);
  }
  for (int spin = 0; spin < 200; ++spin) {  // ≤ 2 s, like resolved.zig
    int status = 0;
    const pid_t r = waitpid(pid, &status, WNOHANG);
    if (r == pid) return WIFEXITED(status) && WEXITSTATUS(status) == 0;
    if (r < 0) return false;
    usleep(10 * 1000);
  }
  kill(pid, SIGKILL);
  waitpid(pid, nullptr, 0);
  return false;
}

static bool ResolvedApply(bool* applied, std::string* note) {
  *applied = false;
  const std::string exe = ResolvedTool();
  if (exe.empty()) {
    *note = "systemd-resolved not in charge — DNS keeps its own upstreams";
    return true;  // not an error (mirrors resolved.zig returning false)
  }
  char dns_addr[] = "172.19.0.2";
  char name1[16], name2[16], name3[16];
  snprintf(name1, sizeof(name1), "%s", kTunName);
  snprintf(name2, sizeof(name2), "%s", kTunName);
  snprintf(name3, sizeof(name3), "%s", kTunName);
  char* argv1[] = {const_cast<char*>("resolvectl"),
                   const_cast<char*>("dns"), name1, dns_addr, nullptr};
  if (!RunTool(exe, argv1)) {
    *note = "resolvectl dns failed — 127.0.0.53 keeps its own upstreams";
    return true;  // resolved.zig logs a warning and returns false
  }
  char* argv2[] = {const_cast<char*>("resolvectl"),
                   const_cast<char*>("domain"), name2,
                   const_cast<char*>("~."), nullptr};
  (void)!RunTool(exe, argv2);
  char* argv3[] = {const_cast<char*>("resolvectl"),
                   const_cast<char*>("default-route"), name3,
                   const_cast<char*>("true"), nullptr};
  (void)!RunTool(exe, argv3);
  *applied = true;
  *note = "systemd-resolved now delegates every domain to the tunnel DNS";
  return true;
}

static void ResolvedRevert() {
  const std::string exe = ResolvedTool();
  if (exe.empty()) return;
  char name[16];
  snprintf(name, sizeof(name), "%s", kTunName);
  char* argv[] = {const_cast<char*>("resolvectl"),
                  const_cast<char*>("revert"), name, nullptr};
  (void)!RunTool(exe, argv);
}

// ---------------------------------------------------------------------------
// The tunnel state machine (one tunnel per helper process).
// ---------------------------------------------------------------------------
class Tunnel {
 public:
  ~Tunnel() { Teardown(); }

  bool Up(uid_t peer_uid, HelperError* err) {
    if (up_) return true;

    Netlink nl;
    if (!nl.Open()) {
      err->msg = "netlink: " + nl.error();
      err->errno_class = EACCES;
      return false;
    }

    // 1. the TUN device (device/linux.zig Tun.open, IFF_TUN|IFF_NO_PI).
    tun_fd_ = OpenTun(err);
    if (tun_fd_ < 0) return false;

    // 2. the interface index.
    if (!IfIndex(kTunName, &if_index_, err)) return false;

    // 3. self-healing: clear any stale rule stragglers of OUR span first
    //    (installAutoRoute's clearRules) — a crashed previous pair can at
    //    most leave these behind.
    ClearRules(&nl);

    // 4. link: MTU + txqueuelen (route/linux.zig setLink(mtu, txqlen)).
    {
      Builder b;
      b.Begin(RTM_NEWLINK, 0, 0);
      IfInfoMsg info;
      memset(&info, 0, sizeof(info));
      info.index = static_cast<int32_t>(if_index_);
      b.Body(info);
      b.AttrU32(IFLA_MTU, kTunMtu);
      b.AttrU32(IFLA_TXQLEN, kTunTxQueueLen);
      if (!nl.Transact(b.Finish(), b.size())) {
        err->msg = "setlink(mtu,txqlen): " + nl.error();
        return false;
      }
    }

    // 5. rp_filter 1 → 2 (the desktop step of configureLink).
    RelaxRpFilter(kTunName);

    // 6. address 172.19.0.1/30 (route/linux.zig address(): IFA_LOCAL +
    //    IFA_ADDRESS; v4 → no IFA_F_NODAD).
    {
      Builder b;
      b.Begin(RTM_NEWADDR, NLM_F_CREATE | NLM_F_REPLACE, 0);
      IfAddrMsg am;
      memset(&am, 0, sizeof(am));
      am.family = AF_INET;
      am.prefixlen = static_cast<uint8_t>(kTunPrefix);
      am.index = if_index_;
      b.Body(am);
      b.Attr(IFA_LOCAL, &kTunAddrHost, 4);
      b.Attr(IFA_ADDRESS, &kTunAddrHost, 4);
      if (!nl.Transact(b.Finish(), b.size())) {
        err->msg = "newaddr(172.19.0.1/30): " + nl.error();
        return false;
      }
    }

    // 7. link UP (configureLink's final setLink(index, true)).
    {
      Builder b;
      b.Begin(RTM_NEWLINK, 0, 0);
      IfInfoMsg info;
      memset(&info, 0, sizeof(info));
      info.index = static_cast<int32_t>(if_index_);
      info.change = IFF_UP_FLAG;
      info.flags = IFF_UP_FLAG;
      b.Body(info);
      if (!nl.Transact(b.Finish(), b.size())) {
        err->msg = "setlink(UP): " + nl.error();
        return false;
      }
    }

    // 8. the default route in table 2022 (installAutoRoute: no include
    //    lists → the 0/0 default, oif = tun).
    if (!AddDefaultRoute(&nl, err)) return false;

    // 9. the four policy rules, in the pinned order:
    //    9009 NOP, 9000 UID→GOTO 9009, 9004 main+suppress_prefixlen,
    //    9005 table 2022 fwmark invert.
    if (!AddRuleNop(&nl, err)) return false;
    if (!AddRuleUid(&nl, peer_uid, err)) return false;
    if (!AddRuleMain(&nl, err)) return false;
    if (!AddRuleFwmark(&nl, err)) return false;

    // 10. resolved delegation (best-effort, like the pinned core).
    std::string resolved_note;
    if (!ResolvedApply(&resolved_applied_, &resolved_note)) {
      resolved_note = "resolved apply failed";
    }
    Log("up: %s", resolved_note.c_str());

    // 11. FAIL-CLOSED VERIFICATION (the owner's "real readiness" decree):
    //     read back the interface, the rules and the route. An `up` answer
    //     means VERIFIED — never "the process was created".
    if (!Verify(&nl, peer_uid, err)) {
      Teardown();
      return false;
    }

    up_ = true;
    Log("up: tun=%s idx=%u uid=%u excluded, table %u, rules %u..%u verified",
        kTunName, if_index_, static_cast<unsigned>(peer_uid), kTable, kRuleBase,
        kRuleBase + kRuleSpan - 1);
    return true;
  }

  int tun_fd() const { return tun_fd_; }
  bool up() const { return up_; }

  void ReleaseTunFd() {
    if (tun_fd_ >= 0) {
      close(tun_fd_);  // the app owns its SCM_RIGHTS copy from here on
      tun_fd_ = -1;
    }
  }

  void Teardown() {
    if (!up_ && tun_fd_ < 0 && !resolved_applied_) return;
    Netlink nl;
    if (nl.Open()) {
      // rules first (route/linux.zig teardown → clearRules)
      ClearRules(&nl);
      // the table-2022 default route (best-effort: the kernel removes it
      // with the interface anyway; this covers a still-open fd)
      Builder b;
      b.Begin(RTM_DELROUTE, 0, 0);
      RtMsg rm;
      memset(&rm, 0, sizeof(rm));
      rm.family = AF_INET;
      rm.dst_len = 0;
      rm.protocol = RTPROT_STATIC;
      rm.scope = RT_SCOPE_LINK;
      rm.kind = RTN_UNICAST;
      b.Body(rm);
      b.AttrU32(RTA_OIF, if_index_);
      b.AttrU32(RTA_TABLE, kTable);
      (void)!nl.Transact(b.Finish(), b.size());
      // the interface itself (guarantees route cleanup even on fd leaks)
      if (if_index_ != 0) {
        Builder b2;
        b2.Begin(RTM_DELLINK, 0, 0);
        IfInfoMsg info;
        memset(&info, 0, sizeof(info));
        info.index = static_cast<int32_t>(if_index_);
        b2.Body(info);
        (void)!nl.Transact(b2.Finish(), b2.size());
      }
    }
    if (resolved_applied_) {
      ResolvedRevert();
      resolved_applied_ = false;
    }
    ReleaseTunFd();
    up_ = false;
    if_index_ = 0;
    Log("teardown: rules %u..%u cleared, route/interface/resolved reverted",
        kRuleBase, kRuleBase + kRuleSpan - 1);
  }

  // The through-tunnel end-to-end probe (the owner's requirement D). Runs as
  // uid 0 — NOT excluded by the uid rule — so the traffic genuinely
  // traverses tun → zeptun → SOCKS5 → the Aether core.
  bool Probe(int timeout_secs, int64_t* elapsed_ms, std::string* detail) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo* res = nullptr;
    const int gai = getaddrinfo(kProbeHost, "80", &hints, &res);
    if (gai != 0 || res == nullptr) {
      *detail = std::string("resolve ") + kProbeHost +
                " failed: " + gai_strerror(gai);
      return false;
    }
    const int fd = socket(res->ai_family, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
      *detail = "socket: " + ErrnoStr(0);
      freeaddrinfo(res);
      return false;
    }
    // nonblocking + poll → bounded connect
    const int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    struct timespec ts0;
    clock_gettime(CLOCK_MONOTONIC, &ts0);
    const auto t0 = static_cast<int64_t>(ts0.tv_sec) * 1000 +
                    ts0.tv_nsec / 1000000;
    int cr = connect(fd, res->ai_addr, res->ai_addrlen);
    if (cr != 0 && errno != EINPROGRESS) {
      *detail = "connect: " + ErrnoStr(0);
      close(fd);
      freeaddrinfo(res);
      return false;
    }
    if (cr != 0) {
      pollfd p{fd, POLLOUT, 0};
      if (poll(&p, 1, timeout_secs * 1000) <= 0) {
        *detail = "connect timeout";
        close(fd);
        freeaddrinfo(res);
        return false;
      }
      int soerr = 0;
      socklen_t slen = sizeof(soerr);
      if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen) != 0 ||
          soerr != 0) {
        *detail = std::string("connect: ") + ErrnoStr(soerr);
        close(fd);
        freeaddrinfo(res);
        return false;
      }
    }
    char req[256];
    const int reqlen = snprintf(req, sizeof(req),
                                "GET %s HTTP/1.0\r\nHost: %s\r\n\r\n",
                                kProbePath, kProbeHost);
    if (write(fd, req, static_cast<size_t>(reqlen)) != reqlen) {
      *detail = "write: " + ErrnoStr(0);
      close(fd);
      freeaddrinfo(res);
      return false;
    }
    pollfd p{fd, POLLIN, 0};
    if (poll(&p, 1, timeout_secs * 1000) <= 0) {
      *detail = "response timeout";
      close(fd);
      freeaddrinfo(res);
      return false;
    }
    char resp[512];
    const ssize_t n = read(fd, resp, sizeof(resp) - 1);
    struct timespec ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts1);
    const auto t1 = static_cast<int64_t>(ts1.tv_sec) * 1000 +
                    ts1.tv_nsec / 1000000;
    close(fd);
    freeaddrinfo(res);
    if (n <= 0) {
      *detail = "read: " + ErrnoStr(0);
      return false;
    }
    resp[n] = 0;
    *elapsed_ms = t1 - t0;
    *detail = std::string("HTTP answer through the tunnel: ") +
              std::string(resp, strnlen(resp, 24));
    return true;
  }

 private:
  void ClearRules(Netlink* nl) {
    for (int v6 = 0; v6 <= 1; ++v6) {
      for (uint32_t p = kRuleBase; p < kRuleBase + kRuleSpan; ++p) {
        Builder b;
        b.Begin(RTM_DELRULE, 0, 0);
        FibRuleHdr fr;
        memset(&fr, 0, sizeof(fr));
        fr.family = v6 ? static_cast<uint8_t>(AF_INET6)
                       : static_cast<uint8_t>(AF_INET);
        fr.action = 0;  // FR_ACT_UNSPEC: delete by priority only
        b.Body(fr);
        b.AttrU32(FRA_PRIORITY, p);
        (void)!nl->Transact(b.Finish(), b.size());  // ENOENT is expected
      }
    }
  }

  bool AddDefaultRoute(Netlink* nl, HelperError* err) {
    Builder b;
    b.Begin(RTM_NEWROUTE, NLM_F_CREATE | NLM_F_REPLACE, 0);
    RtMsg rm;
    memset(&rm, 0, sizeof(rm));
    rm.family = AF_INET;
    rm.dst_len = 0;              // 0/0
    rm.table = RT_TABLE_UNSPEC;  // 2022 ≥ 256 → the attr carries it
    rm.protocol = RTPROT_STATIC;
    rm.scope = RT_SCOPE_LINK;    // no gateway
    rm.kind = RTN_UNICAST;
    b.Body(rm);
    b.AttrU32(RTA_OIF, if_index_);
    b.AttrU32(RTA_TABLE, kTable);
    if (!nl->Transact(b.Finish(), b.size())) {
      err->msg = "newroute(0/0 → table " + std::to_string(kTable) +
                 "): " + nl->error();
      return false;
    }
    return true;
  }

  bool AddRuleNop(Netlink* nl, HelperError* err) {
    Builder b;
    b.Begin(RTM_NEWRULE, NLM_F_CREATE | NLM_F_EXCL, 0);
    FibRuleHdr fr;
    memset(&fr, 0, sizeof(fr));
    fr.family = AF_INET;
    fr.action = FR_ACT_NOP;
    b.Body(fr);
    b.AttrU32(FRA_PRIORITY, kRuleBase + kRuleSpan - 1);
    if (!nl->Transact(b.Finish(), b.size()) && nl->last_errno() != EEXIST) {
      err->msg = "newrule(nop " + std::to_string(kRuleBase + kRuleSpan - 1) +
                 "): " + nl->error();
      return false;
    }
    return true;
  }

  bool AddRuleUid(Netlink* nl, uid_t uid, HelperError* err) {
    Builder b;
    b.Begin(RTM_NEWRULE, NLM_F_CREATE | NLM_F_EXCL, 0);
    FibRuleHdr fr;
    memset(&fr, 0, sizeof(fr));
    fr.family = AF_INET;
    fr.action = FR_ACT_GOTO;
    b.Body(fr);
    b.AttrU32(FRA_PRIORITY, kRuleBase);
    b.AttrU32(FRA_GOTO, kRuleBase + kRuleSpan - 1);
    const uint32_t range[2] = {uid, uid};
    b.Attr(FRA_UID_RANGE, range, sizeof(range));
    if (!nl->Transact(b.Finish(), b.size()) && nl->last_errno() != EEXIST) {
      err->msg = "newrule(uid " + std::to_string(uid) + " → goto): " +
                 nl->error();
      return false;
    }
    return true;
  }

  bool AddRuleMain(Netlink* nl, HelperError* err) {
    Builder b;
    b.Begin(RTM_NEWRULE, NLM_F_CREATE | NLM_F_EXCL, 0);
    FibRuleHdr fr;
    memset(&fr, 0, sizeof(fr));
    fr.family = AF_INET;
    fr.table = static_cast<uint8_t>(RT_TABLE_MAIN);  // 254 < 256 → inline
    fr.action = FR_ACT_TO_TBL;
    b.Body(fr);
    b.AttrU32(FRA_PRIORITY, kRuleBase + 4);
    b.AttrU32(FRA_TABLE, RT_TABLE_MAIN);
    b.AttrU32(FRA_SUPPRESS_PREFIXLEN, 0);
    if (!nl->Transact(b.Finish(), b.size()) && nl->last_errno() != EEXIST) {
      err->msg = "newrule(main lookup): " + nl->error();
      return false;
    }
    return true;
  }

  bool AddRuleFwmark(Netlink* nl, HelperError* err) {
    Builder b;
    b.Begin(RTM_NEWRULE, NLM_F_CREATE | NLM_F_EXCL, 0);
    FibRuleHdr fr;
    memset(&fr, 0, sizeof(fr));
    fr.family = AF_INET;
    fr.action = FR_ACT_TO_TBL;
    fr.flags = FIB_RULE_INVERT;
    b.Body(fr);
    b.AttrU32(FRA_PRIORITY, kRuleBase + 5);
    b.AttrU32(FRA_TABLE, kTable);
    b.AttrU32(FRA_FWMARK, kFwmark);
    b.AttrU32(FRA_FWMASK, kFwmask);
    if (!nl->Transact(b.Finish(), b.size()) && nl->last_errno() != EEXIST) {
      err->msg = "newrule(fwmark → table " + std::to_string(kTable) +
                 "): " + nl->error();
      return false;
    }
    return true;
  }

  // Fail-closed read-back: the interface must exist, all four rules must be
  // present with the right shape, and the default route must sit in the
  // table — or the tunnel refuses to report `up`.
  bool Verify(Netlink* nl, uid_t peer_uid, HelperError* err) {
    uint32_t idx = 0;
    if (!IfIndex(kTunName, &idx, err) || idx != if_index_) {
      err->msg = "verify: the TUN interface disappeared during bring-up";
      return false;
    }
    bool have_uid = false, have_main = false, have_fwmark = false,
         have_nop = false;
    const bool ok = nl->DumpRules(
        AF_INET, [&](const FibRuleHdr& fr, const uint8_t* attrs,
                     size_t attrs_len) {
          uint32_t priority = 0xffffffffu, table = 0, fwmark = 0;
          const uint32_t* uid_range = nullptr;
          size_t off = 0;
          while (off + 4 <= attrs_len) {
            uint16_t alen, akind;
            memcpy(&alen, attrs + off, 2);
            memcpy(&akind, attrs + off + 2, 2);
            if (alen < 4 || off + alen > attrs_len) break;
            const uint8_t* data = attrs + off + 4;
            const size_t dlen = alen - 4;
            if (akind == FRA_PRIORITY && dlen >= 4) memcpy(&priority, data, 4);
            if (akind == FRA_TABLE && dlen >= 4) memcpy(&table, data, 4);
            if (akind == FRA_FWMARK && dlen >= 4) memcpy(&fwmark, data, 4);
            if (akind == FRA_UID_RANGE && dlen >= 8) {
              uid_range = reinterpret_cast<const uint32_t*>(data);
            }
            off += (alen + 3) & ~static_cast<size_t>(3);
          }
          if (fr.action == FR_ACT_NOP && priority == kRuleBase + kRuleSpan - 1) {
            have_nop = true;
          }
          if (fr.action == FR_ACT_GOTO && priority == kRuleBase && uid_range &&
              uid_range[0] == peer_uid && uid_range[1] == peer_uid) {
            have_uid = true;
          }
          if (fr.action == FR_ACT_TO_TBL && priority == kRuleBase + 4 &&
              table == RT_TABLE_MAIN) {
            have_main = true;
          }
          if (fr.action == FR_ACT_TO_TBL && (fr.flags & FIB_RULE_INVERT) &&
              priority == kRuleBase + 5 && table == kTable &&
              fwmark == kFwmark) {
            have_fwmark = true;
          }
        });
    if (!ok) {
      err->msg = "verify: rule dump failed: " + nl->error();
      return false;
    }
    if (!(have_nop && have_uid && have_main && have_fwmark)) {
      err->msg = "verify: policy rules incomplete after install (nop=" +
                 std::string(have_nop ? "y" : "n") + " uid=" +
                 (have_uid ? "y" : "n") + " main=" + (have_main ? "y" : "n") +
                 " fwmark=" + (have_fwmark ? "y" : "n") + ")";
      return false;
    }
    bool have_default = false;
    const bool ok2 = nl->DumpRoutes(
        AF_INET, kTable,
        [&](const RtMsg& rm2, const uint8_t* attrs, size_t attrs_len) {
          if (rm2.dst_len != 0) return;
          size_t off = 0;
          while (off + 4 <= attrs_len) {
            uint16_t alen, akind;
            memcpy(&alen, attrs + off, 2);
            memcpy(&akind, attrs + off + 2, 2);
            if (alen < 4 || off + alen > attrs_len) break;
            if (akind == RTA_OIF && alen - 4 >= 4) {
              uint32_t oif = 0;
              memcpy(&oif, attrs + off + 4, 4);
              if (oif == if_index_) have_default = true;
            }
            off += (alen + 3) & ~static_cast<size_t>(3);
          }
        });
    if (!ok2) {
      err->msg = "verify: route dump failed: " + nl->error();
      return false;
    }
    if (!have_default) {
      err->msg = "verify: the default route is missing from table " +
                 std::to_string(kTable);
      return false;
    }
    return true;
  }

  int tun_fd_ = -1;
  uint32_t if_index_ = 0;
  bool up_ = false;
  bool resolved_applied_ = false;
};

// The dump helpers.
bool Netlink::SendDump(uint16_t kind, const void* hdr, size_t hdr_len) {
  Builder b;
  b.Begin(kind, NLM_F_DUMP | NLM_F_ACK, seq_++);
  b.Body(hdr, hdr_len);
  // Strip NLM_F_ACK: the dump stream ends with NLMSG_DONE. An extra ACK
  // arriving AFTER the DONE would stay unread and poison the NEXT dump's
  // read loop (it would stop at the stray NLMSG_ERROR instead of DONE).
  {
    uint16_t flags = 0;
    memcpy(&flags, const_cast<uint8_t*>(b.Finish()) + 6, 2);
    flags = static_cast<uint16_t>(flags & ~NLM_F_ACK);
    memcpy(const_cast<uint8_t*>(b.Finish()) + 6, &flags, 2);
  }
  SockaddrNl dst;
  memset(&dst, 0, sizeof(dst));
  dst.nl_family = AF_NETLINK;
  if (sendto(fd_, b.Finish(), b.size(), 0, reinterpret_cast<sockaddr*>(&dst),
             sizeof(dst)) < 0) {
    err_ = "dump sendto: " + ErrnoStr(0);
    return false;
  }
  return true;
}

bool Netlink::DumpRules(
    uint8_t family,
    const std::function<void(const FibRuleHdr&, const uint8_t*, size_t)>&
        on_rule) {
  FibRuleHdr fr;
  memset(&fr, 0, sizeof(fr));
  fr.family = family;
  fr.action = FR_ACT_TO_TBL;
  if (!SendDump(RTM_GETRULE, &fr, sizeof(fr))) return false;
  uint8_t buf[16384] __attribute__((aligned(4)));
  bool done = false;
  for (int rounds = 0; rounds < 64 && !done; ++rounds) {
    const ssize_t got = recv(fd_, buf, sizeof(buf), 0);
    if (got < 0) {
      if (errno == EINTR) continue;
      err_ = "dump recv: " + ErrnoStr(0);
      return false;
    }
    if (got == 0) return true;
    size_t off = 0;
    const size_t total = static_cast<size_t>(got);
    while (off + sizeof(NlMsgHdr) <= total) {
      NlMsgHdr h;
      memcpy(&h, buf + off, sizeof(h));
      if (h.len < sizeof(NlMsgHdr) || off + h.len > total) break;
      if (h.kind == NLMSG_DONE || h.kind == NLMSG_ERROR) {
        done = true;
        break;
      }
      if (h.kind == RTM_NEWRULE && h.len >= sizeof(NlMsgHdr) + sizeof(FibRuleHdr)) {
        FibRuleHdr body;
        memcpy(&body, buf + off + sizeof(NlMsgHdr), sizeof(body));
        const size_t hdr = (sizeof(NlMsgHdr) + sizeof(FibRuleHdr) + 3) & ~3u;
        on_rule(body, buf + off + hdr, h.len - hdr);
      }
      off += (h.len + 3) & ~3u;
    }
  }
  return true;
}

bool Netlink::DumpRoutes(
    uint8_t family, uint32_t table,
    const std::function<void(const RtMsg&, const uint8_t*, size_t)>&
        on_route) {
  RtMsg rm;
  memset(&rm, 0, sizeof(rm));
  rm.family = family;
  rm.table = 0;  // filter by the RTA_TABLE attribute instead
  if (!SendDump(RTM_GETROUTE, &rm, sizeof(rm))) return false;
  uint8_t buf[16384] __attribute__((aligned(4)));
  bool done = false;
  for (int rounds = 0; rounds < 64 && !done; ++rounds) {
    const ssize_t got = recv(fd_, buf, sizeof(buf), 0);
    if (got < 0) {
      if (errno == EINTR) continue;
      err_ = "dump recv: " + ErrnoStr(0);
      return false;
    }
    if (got == 0) return true;
    size_t off = 0;
    const size_t total = static_cast<size_t>(got);
    while (off + sizeof(NlMsgHdr) <= total) {
      NlMsgHdr h;
      memcpy(&h, buf + off, sizeof(h));
      if (h.len < sizeof(NlMsgHdr) || off + h.len > total) break;
      if (h.kind == NLMSG_DONE || h.kind == NLMSG_ERROR) {
        done = true;
        break;
      }
      if (h.kind == RTM_NEWROUTE && h.len >= sizeof(NlMsgHdr) + sizeof(RtMsg)) {
        RtMsg body;
        memcpy(&body, buf + off + sizeof(NlMsgHdr), sizeof(body));
        const size_t hdr = (sizeof(NlMsgHdr) + sizeof(RtMsg) + 3) & ~3u;
        const uint8_t* attrs = buf + off + hdr;
        const size_t attrs_len = h.len - hdr;
        uint32_t rta_table = body.table;
        size_t off2 = 0;
        while (off2 + 4 <= attrs_len) {
          uint16_t alen, akind;
          memcpy(&alen, attrs + off2, 2);
          memcpy(&akind, attrs + off2 + 2, 2);
          if (alen < 4 || off2 + alen > attrs_len) break;
          if (akind == RTA_TABLE && alen >= 8) {
            memcpy(&rta_table, attrs + off2 + 4, 4);
          }
          off2 += (alen + 3) & ~static_cast<size_t>(3);
        }
        if (rta_table == table) on_route(body, attrs, attrs_len);
      }
      off += (h.len + 3) & ~3u;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// --serve: the one-client daemon.
// ---------------------------------------------------------------------------
static int Serve(const char* sock_path) {
  if (geteuid() != 0) {
    Log("refusing to serve unprivileged (euid=%d) — pkexec must launch me",
        static_cast<int>(geteuid()));
    return 2;
  }

  // The socket directory's owner is the invoking user (XDG_RUNTIME_DIR is
  // 0700 user-owned) — the ONLY uid allowed to talk to us.
  struct stat st;
  if (lstat(sock_path, &st) == 0) {
    if (!S_ISSOCK(st.st_mode)) {
      Log("refusing to remove a non-socket path: %s", sock_path);
      return 2;
    }
    if (unlink(sock_path) != 0) {
      Log("stale socket could not be removed: %s", sock_path);
      return 2;
    }
  }
  std::string dir(sock_path);
  {
    const size_t slash = dir.find_last_of('/');
    if (slash == std::string::npos) return 2;
    dir = dir.substr(0, slash);
  }
  if (stat(dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
    Log("socket directory missing/not a dir: %s", dir.c_str());
    return 2;
  }
  const uid_t allowed_uid = st.st_uid;
  if (allowed_uid == 0) {
    Log("refusing a root-owned socket dir (%s) — the app must own it",
        dir.c_str());
    return 2;
  }

  const int lfd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (lfd < 0) {
    Log("unix socket: %s", ErrnoStr(0).c_str());
    return 2;
  }
  sockaddr_un sa;
  memset(&sa, 0, sizeof(sa));
  sa.sun_family = AF_UNIX;
  strncpy(sa.sun_path, sock_path, sizeof(sa.sun_path) - 1);
  if (bind(lfd, reinterpret_cast<sockaddr*>(&sa), sizeof(sa)) < 0) {
    Log("bind(%s): %s", sock_path, ErrnoStr(0).c_str());
    close(lfd);
    return 2;
  }
  if (chmod(sock_path, 0600) != 0 || listen(lfd, 1) < 0) {
    Log("listen(%s): %s", sock_path, ErrnoStr(0).c_str());
    close(lfd);
    unlink(sock_path);
    return 2;
  }
  Log("serving on %s (client uid must be %u)", sock_path,
      static_cast<unsigned>(allowed_uid));

  // One client. A second connect attempt finds the listener closed.
  const int cfd = accept4(lfd, nullptr, nullptr, SOCK_CLOEXEC);
  close(lfd);
  if (cfd < 0) {
    Log("accept: %s", ErrnoStr(0).c_str());
    unlink(sock_path);
    return 2;
  }
  // SO_PEERCRED: the caller's uid/pid, set by the kernel — unspoofable.
  struct UCred {
    pid_t pid;
    uid_t uid;
    gid_t gid;
  } cred;
  socklen_t clen = sizeof(cred);
  if (getsockopt(cfd, SOL_SOCKET, SO_PEERCRED, &cred, &clen) != 0 ||
      cred.uid == 0 || cred.uid != allowed_uid) {
    Log("client rejected (uid=%u, expected %u) — closing",
        static_cast<unsigned>(cred.uid), static_cast<unsigned>(allowed_uid));
    close(cfd);
    unlink(sock_path);
    return 2;
  }
  Log("client accepted (uid=%u pid=%d)", static_cast<unsigned>(cred.uid),
      cred.pid);

  Tunnel tunnel;
  char line[64];
  int rc = 0;
  for (;;) {
    ssize_t n = 0;
    size_t have = 0;
    while (have < sizeof(line) - 1) {
      n = read(cfd, line + have, 1);  // byte-at-a-time: tiny protocol
      if (n <= 0) break;
      if (line[have] == '\n') break;
      ++have;
    }
    if (n <= 0) {  // EOF or error — the app went away
      Log("client gone (%s) — tearing down", n == 0 ? "EOF" : "error");
      break;
    }
    line[have] = 0;
    while (have > 0 && (line[have - 1] == '\r' || line[have - 1] == '\n')) {
      line[--have] = 0;
    }
    if (strcmp(line, "up") == 0) {
      HelperError err;
      if (tunnel.Up(cred.uid, &err)) {
        // send the fd with SCM_RIGHTS (a raw control buffer: cmsghdr itself
        // carries a flexible array member and cannot be embedded in a struct)
        char control_buf[CMSG_SPACE(sizeof(int))];
        memset(control_buf, 0, sizeof(control_buf));
        const int tun_fd = tunnel.tun_fd();
        cmsghdr* ch = reinterpret_cast<cmsghdr*>(control_buf);
        ch->cmsg_len = CMSG_LEN(sizeof(int));
        ch->cmsg_level = SOL_SOCKET;
        ch->cmsg_type = SCM_RIGHTS;
        memcpy(CMSG_DATA(ch), &tun_fd, sizeof(int));
        iovec iov;
        iov.iov_base = const_cast<char*>("OK\n");
        iov.iov_len = 3;
        msghdr sockmsg;
        memset(&sockmsg, 0, sizeof(sockmsg));
        sockmsg.msg_iov = &iov;
        sockmsg.msg_iovlen = 1;
        sockmsg.msg_control = control_buf;
        sockmsg.msg_controllen = sizeof(control_buf);
        const ssize_t sent = sendmsg(cfd, &sockmsg, 0);
        tunnel.ReleaseTunFd();  // the app owns the data plane now
        if (sent < 0) {
          Log("sendmsg(fd) failed: %s — tearing down", ErrnoStr(0).c_str());
          tunnel.Teardown();
          rc = 2;
          break;
        }
        Log("up: fd handed to the app");
      } else {
        char resp[512];
        snprintf(resp, sizeof(resp), "ERR %s\n", err.msg.c_str());
        (void)!write(cfd, resp, strlen(resp));
        Log("up FAILED: %s", err.msg.c_str());
        tunnel.Teardown();
        // stay alive: the app reports the failure and may retry
      }
    } else if (strcmp(line, "down") == 0) {
      tunnel.Teardown();
      (void)!write(cfd, "OK\n", 3);
    } else if (strcmp(line, "probe") == 0) {
      int64_t ms = 0;
      std::string detail;
      char resp[512];
      if (!tunnel.up()) {
        snprintf(resp, sizeof(resp), "ERR tunnel is not up\n");
      } else if (tunnel.Probe(20, &ms, &detail)) {
        snprintf(resp, sizeof(resp), "OK %lld %s\n",
                 static_cast<long long>(ms), detail.c_str());
      } else {
        snprintf(resp, sizeof(resp), "ERR %s\n", detail.c_str());
      }
      (void)!write(cfd, resp, strlen(resp));
      Log("probe: %.*s", 120, resp);
    } else if (strcmp(line, "bye") == 0) {
      Log("client said bye");
      break;
    } else {
      (void)!write(cfd, "ERR unknown command\n", 20);
      Log("unknown command rejected: %s", line);
    }
  }

  tunnel.Teardown();  // idempotent
  close(cfd);
  unlink(sock_path);
  Log("serve: done (rc=%d)", rc);
  return rc;
}

// ---------------------------------------------------------------------------
// --selftest: bring the whole privileged path up and back down, verifying
// both directions. For CI (sudo) and manual diagnosis. Needs root.
// ---------------------------------------------------------------------------
static int SelfTest() {
  if (geteuid() != 0) {
    fprintf(stderr,
            "selftest must run as root (sudo aethone-tunnel-helper --selftest)\n");
    return 2;
  }
  Log("selftest: bring-up");
  Tunnel tunnel;
  HelperError err;
  // NOTE: the uid here only shapes the uid-rule; Verify checks it back, so
  // any non-zero uid exercises the same path. 1000 = the CI runner user.
  if (!tunnel.Up(1000, &err)) {
    fprintf(stderr, "SELFTEST FAIL (up): %s\n", err.msg.c_str());
    return 1;
  }
  const int fd = tunnel.tun_fd();
  if (fd < 0) {
    fprintf(stderr, "SELFTEST FAIL: no tun fd\n");
    return 1;
  }
  fprintf(stderr, "selftest: tun fd alive (flags=%o), %s verified\n",
          fcntl(fd, F_GETFL), kTunName);
  tunnel.ReleaseTunFd();
  tunnel.Teardown();
  // verify the teardown really removed our rules and the interface
  Netlink nl;
  if (!nl.Open()) {
    fprintf(stderr, "SELFTEST FAIL (netlink reopen): %s\n",
            nl.error().c_str());
    return 1;
  }
  int ours = 0;
  nl.DumpRules(AF_INET, [&](const FibRuleHdr&, const uint8_t* attrs,
                            size_t attrs_len) {
    size_t off = 0;
    while (off + 4 <= attrs_len) {
      uint16_t alen, akind;
      memcpy(&alen, attrs + off, 2);
      memcpy(&akind, attrs + off + 2, 2);
      if (alen < 4 || off + alen > attrs_len) break;
      if (akind == FRA_PRIORITY && alen >= 8) {
        uint32_t p = 0;
        memcpy(&p, attrs + off + 4, 4);
        if (p >= kRuleBase && p < kRuleBase + kRuleSpan) ++ours;
      }
      off += (alen + 3) & ~static_cast<size_t>(3);
    }
  });
  uint32_t idx = 0;
  HelperError e2;
  const bool iface_gone = !IfIndex(kTunName, &idx, &e2);
  if (ours != 0 || !iface_gone) {
    fprintf(stderr, "SELFTEST FAIL (teardown): %d rules remain, iface %s\n",
            ours, iface_gone ? "gone" : "STILL PRESENT");
    return 1;
  }
  fprintf(stderr, "SELFTEST PASS: up → verified → down → clean\n");
  return 0;
}

static void Usage(FILE* out) {
  fprintf(out,
          "aethone-tunnel-helper — the AETHONE Linux privilege helper\n"
          "  --serve <socket-path>   one-client daemon (launched via pkexec)\n"
          "  --self-install          install myself + the Polkit action system-wide\n"
          "                           (run as root: pkexec /usr/bin/env <me> --self-install)\n"
          "  --selftest              bring-up/teardown self test (root)\n"
          "  --version               print the protocol version\n");
}

// --self-install: copies THIS executable to /usr/libexec and writes the
// Polkit action, both root-owned with the modes pkexec's path security
// requires. Runs as root (via `pkexec /usr/bin/env <bundle-path>
// --self-install` — env is a root-owned system binary, so pkexec's refusal
// to execute user-writable bundle paths does not apply; the admin password
// authorizes exactly this one bootstrap).
static int SelfInstall() {
  if (geteuid() != 0) {
    fprintf(stderr, "self-install must run as root\n");
    return 2;
  }
  char self_path[4096];
  const ssize_t n = readlink("/proc/self/exe", self_path,
                             sizeof(self_path) - 1);
  if (n <= 0) {
    fprintf(stderr, "self-install: cannot resolve /proc/self/exe\n");
    return 1;
  }
  self_path[n] = 0;
  Log("self-install: %s -> %s", self_path, kHelperInstallPath);

  // 1. the binary: copy + root ownership + 0755 (a rename would carry the
  //    user-writable bundle dir's parent perms into the check, so copy).
  const int in = open(self_path, O_RDONLY | O_CLOEXEC);
  if (in < 0) {
    fprintf(stderr, "self-install: open(%s): %s\n", self_path, strerror(errno));
    return 1;
  }
  const int out = open(kHelperInstallPath,
                       O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0755);
  if (out < 0) {
    fprintf(stderr, "self-install: open(%s): %s\n", kHelperInstallPath,
            strerror(errno));
    close(in);
    return 1;
  }
  char buf[65536];
  ssize_t got;
  while ((got = read(in, buf, sizeof(buf))) > 0) {
    ssize_t off = 0;
    while (off < got) {
      const ssize_t w = write(out, buf + off, static_cast<size_t>(got - off));
      if (w <= 0) {
        fprintf(stderr, "self-install: write: %s\n", strerror(errno));
        close(in);
        close(out);
        return 1;
      }
      off += w;
    }
  }
  close(in);
  if (fsync(out) != 0) {
    Log("self-install: fsync warning: %s", strerror(errno));
  }
  close(out);
  if (chown(kHelperInstallPath, 0, 0) != 0 ||
      chmod(kHelperInstallPath, 0755) != 0) {
    fprintf(stderr, "self-install: chown/chmod failed: %s\n", strerror(errno));
    return 1;
  }

  // 2. the Polkit action (embedded, verbatim).
  const int pf = open(kHelperPolicyInstallPath,
                      O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (pf < 0) {
    fprintf(stderr, "self-install: open(%s): %s\n", kHelperPolicyInstallPath,
            strerror(errno));
    return 1;
  }
  size_t len = strlen(kPolicyXml);
  ssize_t off2 = 0;
  while (off2 < static_cast<ssize_t>(len)) {
    const ssize_t w = write(pf, kPolicyXml + off2, len - static_cast<size_t>(off2));
    if (w <= 0) {
      fprintf(stderr, "self-install: policy write: %s\n", strerror(errno));
      close(pf);
      return 1;
    }
    off2 += w;
  }
  close(pf);
  if (chown(kHelperPolicyInstallPath, 0, 0) != 0 ||
      chmod(kHelperPolicyInstallPath, 0644) != 0) {
    fprintf(stderr, "self-install: policy chown/chmod failed: %s\n",
            strerror(errno));
    return 1;
  }

  // 3. fail-closed verification of BOTH artifacts.
  struct stat st;
  if (stat(kHelperInstallPath, &st) != 0 || st.st_uid != 0 ||
      (st.st_mode & 0222) != 0 || access(kHelperInstallPath, X_OK) != 0) {
    fprintf(stderr, "self-install: verification failed for the binary\n");
    return 1;
  }
  if (stat(kHelperPolicyInstallPath, &st) != 0 || st.st_uid != 0) {
    fprintf(stderr, "self-install: verification failed for the policy\n");
    return 1;
  }
  Log("self-install: OK (helper + Polkit action installed)");
  fprintf(stderr, "SELF-INSTALL OK\n");
  return 0;
}

int main(int argc, char** argv) {
  signal(SIGCHLD, SIG_DFL);
  if (argc == 2 && strcmp(argv[1], "--version") == 0) {
    printf("aethone-tunnel-helper 1\n");
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "--selftest") == 0) return SelfTest();
  if (argc == 2 && strcmp(argv[1], "--self-install") == 0) {
    return SelfInstall();
  }
  if (argc == 3 && strcmp(argv[1], "--serve") == 0) return Serve(argv[2]);
  Usage(argc > 1 ? stderr : stdout);
  return argc > 1 ? 2 : 0;
}
