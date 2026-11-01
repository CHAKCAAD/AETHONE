#!/usr/bin/env python3
# AETHONE — synthetic multi-PT_GNU_RELRO fixture generator (bundle v4 test).
#
# Purpose: prove that scripts/inspect_elf.sh v4 analyzes EVERY PT_GNU_RELRO
# segment independently. Real toolchains emit at most one RELRO segment per
# file, so a hand-crafted minimal ELF64 is the only honest way to exercise
# the multi-segment path. These fixtures are SYNTHETIC TEST OBJECTS:
# not AETHONE build products, not upstream artifacts, never shipped.
#
#   fixture A (aggregate FAIL): seg1 own-load PASS, seg2 shared-load FAIL
#     LOAD#1 RX  off=vaddr=0x1000 filesz=memsz=0x40 align=0x1000
#     LOAD#2 RW  off=vaddr=0x4000 filesz=memsz=0x100 align=0x1000
#     RELRO#1    off=vaddr=0x1000 filesz=memsz=0x40  (== LOAD#1 -> own-load;
#                prot range [0x1000,0x4000); LOAD#2 at 0x4000 >= end -> PASS)
#     RELRO#2    off=vaddr=0x4040 filesz=memsz=0x20  (inside LOAD#2 ->
#                shared-load; (0x4040+0x20)%16384 != 0, covering LOAD
#                writable -> FAIL per the official formula)
#   fixture B (aggregate PASS): both segments own-load PASS
#     LOAD#1 RX  0x1000/0x40 ; LOAD#2 RW 0x4000/0x40
#     RELRO#1 == LOAD#1 exactly ; RELRO#2 == LOAD#2 exactly
#
# Usage: python3 make_relro_multiseg_fixture.py <out_dir>
import struct, sys

def elf64(phdrs, data_len=0x5000):
    # ELF64 little-endian, EM_X86_64 (62), ET_DYN
    e_ident = b'\x7fELF' + bytes([2, 1, 1, 0]) + b'\x00' * 8
    e_type, e_machine = 3, 62
    e_entry = 0x1000
    e_phoff = 64
    e_ehsize, e_phentsize, e_phnum = 64, 56, len(phdrs)
    e_shoff, e_shentsize, e_shnum, e_shstrndx = 0, 0, 0, 0
    eh = struct.pack('<16sHHIQQQIHHHHHH', e_ident, e_type, e_machine, 1,
                     e_entry, e_phoff, e_shoff, 0, e_ehsize, e_phentsize,
                     e_phnum, e_shentsize, e_shnum, e_shstrndx)
    blob = bytearray(eh)
    for p_type, p_flags, p_off, p_vaddr, p_filesz, p_memsz, p_align in phdrs:
        blob += struct.pack('<IIQQQQQQ', p_type, p_flags, p_off, p_vaddr,
                            p_vaddr, p_filesz, p_memsz, p_align)
    blob += bytes(data_len)          # file padding so offsets/sizes exist
    return bytes(blob)

PT_LOAD, PT_GNU_RELRO = 1, 0x6474e552
PF_X, PF_W, PF_R = 1, 2, 4

def out(name, phdrs):
    with open(name, 'wb') as f:
        f.write(elf64(phdrs))
    print(f"wrote {name} ({len(phdrs)} phdrs)")

def main(outdir):
    # fixture A: seg1 PASS (own-load), seg2 FAIL (shared-load, writable LOAD)
    out(f"{outdir}/relro_multiseg_A_fail",
        [(PT_LOAD, PF_R | PF_X, 0x1000, 0x1000, 0x40, 0x40, 0x1000),
         (PT_LOAD, PF_R | PF_W, 0x4000, 0x4000, 0x100, 0x100, 0x1000),
         (PT_GNU_RELRO, PF_R, 0x1000, 0x1000, 0x40, 0x40, 8),
         (PT_GNU_RELRO, PF_R, 0x4040, 0x4040, 0x20, 0x20, 8)])
    # fixture B: both segments own-load PASS
    out(f"{outdir}/relro_multiseg_B_pass",
        [(PT_LOAD, PF_R | PF_X, 0x1000, 0x1000, 0x40, 0x40, 0x1000),
         (PT_LOAD, PF_R | PF_W, 0x4000, 0x4000, 0x40, 0x40, 0x1000),
         (PT_GNU_RELRO, PF_R, 0x1000, 0x1000, 0x40, 0x40, 8),
         (PT_GNU_RELRO, PF_R, 0x4000, 0x4000, 0x40, 0x40, 8)])

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
