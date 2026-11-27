#!/usr/bin/env python3
"""Android app-seccomp gate for native libraries (x86_64 and arm64).

Android's app seccomp filter (bionic SECCOMP_ALLOWLIST_APP / _COMMON +
SYSCALLS.TXT) does NOT admit the legacy syscalls poll(2), select(2),
epoll_wait(2), access(2), stat(2), ... for 64-bit apps; a raw call kills the
whole app process with SIGSYS (SYS_SECCOMP). AETHONE hit exactly this:
zeptun's epoll backend issued `poll` (x86_64 nr 7) on the first routed TCP
flow (CI run 45870688624, tombstone_00).

Zig code built without bionic issues syscalls directly (`mov $NR,%eax;
syscall`), so the check disassembles every executable section of the given
ELF files and, for each `syscall` (x86_64) / `svc #0` (arm64) instruction,
recovers the syscall number from the nearest preceding write to eax/rax
(x8/w8 on arm64) in the same straight-line block (immediates, `push imm;
pop reg`, register copies). It FAILS when a site uses a number on the deny
list below. Sites whose number is not a constant in straight-line code are
listed as warnings with their address so a reviewer can look at them.

Libc imports (bionic `poll`, `open`, ...) are fine: bionic implements them
with ppoll/openat. Usage: check_android_seccomp.py LIB.so [LIB.so ...]
Exit 0 = clean, 1 = denied syscall found, 2 = usage/tool error.
"""
import sys

try:
    import capstone
    from elftools.elf.elffile import ELFFile
except ImportError as e:  # pragma: no cover
    print(f"::error::check_android_seccomp: missing python module ({e}); pip install capstone pyelftools")
    sys.exit(2)

# Legacy syscalls that the Android app seccomp filter rejects for 64-bit
# processes (x86_64 numbers). `open` (2) and `getdents` (78) are admitted on
# x86_64 (b/34813887) but zeptun is held to the *at variants anyway.
DENY_X86_64 = {
    2: "open", 4: "stat", 6: "lstat", 7: "poll", 21: "access", 22: "pipe",
    23: "select", 33: "dup2", 34: "pause", 37: "alarm", 57: "fork",
    58: "vfork", 82: "rename", 83: "mkdir", 84: "rmdir", 85: "creat",
    86: "link", 87: "unlink", 88: "symlink", 89: "readlink", 90: "chmod",
    92: "chown", 94: "lchown", 111: "getpgrp", 132: "utime", 133: "mknod",
    201: "time", 213: "epoll_create", 232: "epoll_wait", 235: "utimes",
    253: "inotify_init", 261: "futimesat", 284: "eventfd",
}
# arm64 has none of the legacy calls; these are the numbers that would only
# appear by mistake (kernel rejects them anyway) — nothing to deny there.
DENY_ARM64 = {}

X86_ACC = {"eax", "rax"}
ARM_ACC = {"w8", "x8"}


STOP = ("ret", "jmp", "call", "b", "bl", "br", "blr", "ud2", "hlt")


def _imm(text):
    try:
        return int(text.lstrip("#$"), 0)
    except ValueError:
        return None


_GP = ["ax", "bx", "cx", "dx", "si", "di", "bp", "sp"]
_ALIAS = {}
for _r in _GP:
    _ALIAS["r" + _r] = _ALIAS["e" + _r] = "r" + _r
for _n in range(8, 16):
    for _suf in ("", "d", "w", "b"):
        _ALIAS[f"r{_n}{_suf}"] = f"r{_n}"
for _n in range(31):
    _ALIAS[f"x{_n}"] = _ALIAS[f"w{_n}"] = f"x{_n}"


def _reg(name):
    return _ALIAS.get(name)


def recover_nr(insns, idx, acc, depth=0):
    """Syscall number held in eax/rax (x86_64) or w8/x8 (arm64) at insns[idx].
    Walks back through straight-line code and follows `mov imm`, `movabs`,
    `movz`, `xor r,r`, the ReleaseSmall idiom `push imm; pop r` and register
    copies (`mov rax, rdx` -> value of rdx). None = not a constant here."""
    want = {_reg(a) for a in acc}
    for back in range(idx - 1, max(idx - 48, -1), -1):
        p = insns[back]
        if p.mnemonic in STOP:
            return None
        ops = p.op_str.replace(" ", "")
        dst = _reg(ops.split(",", 1)[0])
        if dst not in want:
            continue
        src = ops.split(",", 1)[1] if "," in ops else ""
        if p.mnemonic in ("mov", "movabs", "movz"):
            v = _imm(src)
            if v is not None:
                return v
            if _reg(src) and depth < 4:
                return recover_nr(insns, back, {src}, depth + 1)
            return None
        if p.mnemonic == "xor" and _reg(src) == dst:
            return 0
        if p.mnemonic == "pop":
            for b2 in range(back - 1, max(back - 8, -1), -1):
                q = insns[b2]
                if q.mnemonic in STOP or q.mnemonic == "pop":
                    return None
                if q.mnemonic == "push":
                    return _imm(q.op_str.strip())
            return None
        return None  # any other write to the register: not a constant
    return None

def scan(path):
    with open(path, "rb") as fh:
        elf = ELFFile(fh)
        mach = elf["e_machine"]
        if mach == "EM_X86_64":
            md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
            deny, acc, is_sys = DENY_X86_64, X86_ACC, lambda i: i.mnemonic == "syscall"
        elif mach == "EM_AARCH64":
            md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
            deny, acc, is_sys = DENY_ARM64, ARM_ACC, lambda i: i.mnemonic == "svc"
        else:
            print(f"{path}: machine {mach} not checked (only x86_64/arm64)")
            return 0, 0, []
        md.detail = False
        md.skipdata = True
        sites, unknown, bad = 0, 0, []
        for sec in elf.iter_sections():
            if not (sec["sh_flags"] & 0x4) or sec["sh_type"] != "SHT_PROGBITS":
                continue
            insns = list(md.disasm(sec.data(), sec["sh_addr"]))
            for idx, ins in enumerate(insns):
                if not is_sys(ins):
                    continue
                sites += 1
                nr = recover_nr(insns, idx, acc)
                if nr is None:
                    unknown += 1
                    print(f"::warning::{path}: {sec.name}+0x{ins.address:x} syscall number not a constant in straight-line code (review)")
                elif nr in deny:
                    bad.append((sec.name, ins.address, nr, deny[nr]))
        return sites, unknown, bad


def self_test():
    """Fixture: hand-assembled x86_64 sequences the gate must classify."""
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    cases = [
        (bytes.fromhex("6a07580f05"), 7),                      # push 7; pop rax; syscall  (ReleaseSmall)
        (bytes.fromhex("b8070000000f05"), 7),                  # mov eax, 7; syscall
        (bytes.fromhex("48b807000000000000000f05"), 7),        # movabs rax, 7; syscall
        (bytes.fromhex("ba070000004889d00f05"), 7),            # mov edx, 7; mov rax, rdx; syscall
        (bytes.fromhex("b80f0100000f05"), 271),                # mov eax, 271 (ppoll); syscall
        (bytes.fromhex("488b07e8000000000f05"), None),         # call in between -> unknown
    ]
    ok = True
    for code, want in cases:
        insns = list(md.disasm(code, 0x1000))
        got = recover_nr(insns, len(insns) - 1, X86_ACC)
        if got != want:
            print(f"::error::self-test: {code.hex()} -> {got}, expected {want}")
            ok = False
    if 7 not in DENY_X86_64 or 271 in DENY_X86_64:
        ok = False
    print("self-test:", "OK" if ok else "FAILED")
    return 0 if ok else 1


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) < 2:
        print(__doc__)
        return 2
    rc = 0
    for path in argv[1:]:
        sites, unknown, bad = scan(path)
        print(f"{path}: {sites} direct syscall sites, {unknown} with a non-constant number, {len(bad)} denied")
        for sec, addr, nr, name in bad:
            why = ("admitted on x86_64 by b/34813887 but AETHONE requires the *at variant"
                   if nr in (2,) else "rejected by the Android app seccomp filter (SIGSYS)")
            print(f"::error::{path}: {sec}+0x{addr:x} issues `{name}` (nr {nr}) — {why}")
            rc = 1
    if rc == 0:
        print("android seccomp gate: OK (no denied legacy syscall issued directly)")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
