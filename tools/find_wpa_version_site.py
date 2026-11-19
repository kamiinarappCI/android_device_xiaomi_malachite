#!/usr/bin/env python3
"""Locate the nl80211 WPA-version selection site in an arm64 wpa_supplicant.

Anchor: the format string logged immediately after the version bits are
computed in nl80211_connect_common():

    wpa_printf(MSG_DEBUG, "  * WPA Versions 0x%x", ver);

The tool finds that string, finds the ADRP/ADD pair in .text that materialises
its address, then disassembles the window before it so the constant-forming
instructions for NL80211_WPA_VERSION_2 (0x2) and _3 (0x4) can be identified.

This only reports. It never writes to the binary.
"""
import argparse
import sys

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
from elftools.elf.elffile import ELFFile

ANCHOR = b"  * WPA Versions 0x%x\x00"


def find_string_vaddr(elf, data):
    off = data.find(ANCHOR)
    if off < 0:
        sys.exit("anchor string not found; is this an Android wpa_supplicant?")
    for sec in elf.iter_sections():
        so = sec['sh_offset']
        ss = sec['sh_size']
        if sec['sh_addr'] and so <= off < so + ss:
            return off, sec['sh_addr'] + (off - so), sec.name
    sys.exit("anchor string is not inside an allocated section")


def text_section(elf):
    sec = elf.get_section_by_name('.text')
    if sec is None:
        sys.exit("no .text section")
    return sec


def find_adrp_add_refs(md, code, base, target):
    """Yield (vaddr_of_adrp, reg, disasm_pair) for ADRP+ADD computing target."""
    insns = list(md.disasm(code, base))
    by_reg = {}
    hits = []
    for i, ins in enumerate(insns):
        m = ins.mnemonic
        if m == 'adrp':
            reg = ins.op_str.split(',')[0].strip()
            try:
                page = int(ins.op_str.split('#')[-1].strip(), 0)
            except ValueError:
                continue
            by_reg[reg] = (page, ins.address, i)
        elif m == 'add':
            parts = [p.strip() for p in ins.op_str.split(',')]
            if len(parts) == 3 and parts[2].startswith('#'):
                src = parts[1]
                if src in by_reg:
                    page, adrp_addr, adrp_i = by_reg[src]
                    try:
                        imm = int(parts[2][1:], 0)
                    except ValueError:
                        continue
                    if page + imm == target:
                        hits.append((adrp_addr, adrp_i, ins.address, i))
    return insns, hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('binary')
    ap.add_argument('--before', type=int, default=40,
                    help='instructions of context before the anchor reference')
    ap.add_argument('--after', type=int, default=8)
    args = ap.parse_args()

    data = open(args.binary, 'rb').read()
    elf = ELFFile(open(args.binary, 'rb'))
    if elf.get_machine_arch() != 'AArch64':
        sys.exit('not an AArch64 ELF: %s' % elf.get_machine_arch())

    off, vaddr, secname = find_string_vaddr(elf, data)
    print('anchor string : file offset 0x%x, vaddr 0x%x, section %s'
          % (off, vaddr, secname))

    text = text_section(elf)
    code = text.data()
    base = text['sh_addr']
    print('.text         : vaddr 0x%x, size 0x%x, file offset 0x%x'
          % (base, text['sh_size'], text['sh_offset']))

    md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    md.detail = False
    insns, hits = find_adrp_add_refs(md, code, base, vaddr)
    if not hits:
        sys.exit('no ADRP/ADD pair computes the anchor address')

    print('references    : %d' % len(hits))
    text_off = text['sh_offset']
    for n, (adrp_addr, adrp_i, add_addr, add_i) in enumerate(hits, 1):
        print()
        print('=== reference %d: ADRP at 0x%x, ADD at 0x%x ===' % (n, adrp_addr, add_addr))
        lo = max(0, adrp_i - args.before)
        hi = min(len(insns), add_i + args.after)
        for ins in insns[lo:hi]:
            file_off = text_off + (ins.address - base)
            mark = ''
            if ins.address in (adrp_addr, add_addr):
                mark = '   <== anchor'
            elif ins.mnemonic in ('mov', 'movz', 'orr', 'csel', 'csinc', 'cinc') \
                    and ('#4' in ins.op_str or '#2' in ins.op_str
                         or '#0x4' in ins.op_str or '#0x2' in ins.op_str):
                mark = '   <== constant'
            print('  0x%08x (file 0x%06x)  %-8s %s%s'
                  % (ins.address, file_off, ins.mnemonic, ins.op_str, mark))


if __name__ == '__main__':
    main()
