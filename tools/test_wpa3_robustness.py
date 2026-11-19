#!/usr/bin/env python3
"""Try to make wpa3.sh patch the wrong thing.

The property under test: `wpa3.sh scan` answers "patch SITE" only for the real
SAE version instruction, and otherwise "none" - never another offset. It is
checked against the stock malachite wpa_supplicant after:

  - every single-bit flip in the five instructions and the log string that
    make up the match (each must leave "none" or the unchanged answer)
  - a second, fully valid copy of the whole pattern elsewhere (ambiguous,
    so "none")
  - thousands of random byte changes away from the pattern (still found)
  - truncation, other architectures and non-ELF input (no answer, no crash)

Run on Linux with the phone's script under dash:

  python3 tools/test_wpa3_robustness.py [stock wpa_supplicant]
"""
import concurrent.futures
import hashlib
import os
import random
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WPA3 = os.path.join(ROOT, 'ksu-module', 'malachite-wpa3-fix', 'wpa3.sh')
STOCK_SHA = 'd8e3d8c5774c843c0c1c5a60afa4d0c91253c8bb154de440da9245e040da1dbc'
SITE = 0x119bfc
ANCHOR = b'  * WPA Versions 0x%x'

tmp = tempfile.mkdtemp()
results = {'pass': 0, 'fail': 0}


def check(name, got, want):
    ok = got in want if isinstance(want, (set, tuple)) else got == want
    results['pass' if ok else 'fail'] += 1
    if not ok:
        print('FAIL  %s  (want %r got %r)' % (name, want, got))
    return ok


def scan_bytes(data, tag):
    p = os.path.join(tmp, tag)
    with open(p, 'wb') as f:
        f.write(data)
    r = subprocess.run(['dash', WPA3, 'scan', p], capture_output=True, text=True, timeout=120)
    os.remove(p)
    return r.stdout.strip() or ('error: ' + r.stderr.strip()[:80])


def scan_many(items):
    """items: list of (name, data, allowed answers) -> checks run in parallel."""
    with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 4) as ex:
        futs = {ex.submit(scan_bytes, d, 'f%d' % i): (n, w) for i, (n, d, w) in enumerate(items)}
        for fut in concurrent.futures.as_completed(futs):
            n, w = futs[fut]
            check(n, fut.result(), w)


def load(path):
    if path:
        return open(path, 'rb').read()
    d = bytearray(open(os.path.join(ROOT, 'ksu-module', 'wpa_supplicant.patched'), 'rb').read())
    d[SITE + 2] = 0x1e
    return bytes(d)


def main():
    stock = load(sys.argv[1] if len(sys.argv) > 1 else None)
    if not check('stock is the analysed build', hashlib.sha256(stock).hexdigest(), STOCK_SHA):
        sys.exit(2)
    patched = bytearray(stock); patched[SITE + 2] = 0x1f; patched = bytes(patched)
    good, done = 'patch %d' % SITE, 'patched %d' % SITE
    check('baseline stock', scan_bytes(stock, 'base'), good)
    check('baseline patched', scan_bytes(patched, 'basep'), done)

    word = lambda d, o: struct.unpack_from('<I', d, o)[0]
    b_target = SITE + 4 + ((word(stock, SITE + 4) & 0x3ffffff) << 2)   # label after "orr #2"
    parts = {'orr #4': SITE, 'b label': SITE + 4, 'orr #2': b_target - 4,
             'adrp': b_target, 'add': b_target + 4}
    anchor_off = stock.find(ANCHOR)

    # 1. every single-bit flip in the matched instructions and string
    items = []
    for name, off in parts.items():
        for bit in range(32):
            d = bytearray(stock); d[off + bit // 8] ^= 1 << (bit % 8)
            # A flip may keep the pattern valid only if it changes nothing the
            # match relies on; the answer must then still be the same site.
            # Bit 16 of "orr #4" is the fix itself (immr 30 -> 31).
            want = done if (name, bit) == ('orr #4', 16) else {good, 'none'}
            items.append(('bit %2d of %s' % (bit, name), bytes(d), want))
    for i in range(len(ANCHOR)):
        d = bytearray(stock); d[anchor_off + i] ^= 0x20
        items.append(('log string byte %d' % i, bytes(d), 'none'))
    scan_many(items)

    # 2. a second, fully valid copy of the pattern -> ambiguous -> none
    phoff, = struct.unpack_from('<Q', stock, 0x20)
    phent, phnum = struct.unpack_from('<HH', stock, 0x36)
    loads = []
    for i in range(phnum):
        t, fl, o, va, pa, fs = struct.unpack_from('<IIQQQQ', stock, phoff + i * phent)
        if t == 1:
            loads.append((o, va, fs, fl))
    o2v = lambda o: next(o - lo + va for lo, va, fs, fl in loads if lo <= o < lo + fs)
    block = stock[SITE:b_target + 8]
    text_lo, _, text_fs, _ = next(l for l in loads if l[3] & 1)       # executable segment
    dup = text_lo + 0x100                                              # far from the site
    d = bytearray(stock); d[dup:dup + len(block)] = block
    t2 = dup + (b_target - SITE)
    anchor_va = o2v(anchor_off)
    pages = ((anchor_va & ~0xfff) - (o2v(t2) & ~0xfff)) >> 12
    adrp = word(stock, b_target) & 0x9f00001f
    adrp |= (pages & 3) << 29 | ((pages >> 2) & 0x7ffff) << 5
    struct.pack_into('<I', d, t2, adrp)
    check('duplicate pattern elsewhere: none', scan_bytes(bytes(d), 'dup'), 'none')
    only = bytearray(d); only[SITE:b_target + 8] = b'\x1f\x20\x03\xd5' * (len(block) // 4)
    check('duplicate alone is found at its own place', scan_bytes(bytes(only), 'dup1'), 'patch %d' % dup)

    # 3. random changes away from the pattern: still exactly the site
    rng = random.Random(6878)
    protect = [(0, 0x40 + phnum * phent), (SITE - 16, b_target + 24), (anchor_off - 4, anchor_off + 32)]
    items = []
    for n in range(40):
        d = bytearray(stock)
        for _ in range(500):
            o = rng.randrange(len(d))
            if not any(a <= o < b for a, b in protect):
                d[o] = rng.randrange(256)
        items.append(('500 random bytes elsewhere #%d' % n, bytes(d), good))
    scan_many(items)

    # 4. malformed and foreign input
    items = [('truncated to %d bytes' % n, stock[:n], 'none') for n in (0, 3, 16, 64, 0x200, SITE, SITE + 8, b_target)]
    x86 = bytearray(stock); x86[0x12:0x14] = struct.pack('<H', 62)
    items.append(('same bytes, machine x86-64', bytes(x86), 'none'))
    elf32 = bytearray(stock); elf32[4] = 1
    items.append(('same bytes, 32-bit class', bytes(elf32), 'none'))
    items.append(('not an ELF', b'#!/bin/sh\necho hi\n' * 1000, 'none'))
    items.append(('random data', bytes(rng.randrange(256) for _ in range(200000)), 'none'))
    scan_many(items)

    print('robustness: %d passed, %d failed' % (results['pass'], results['fail']))
    return 0 if results['fail'] == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
