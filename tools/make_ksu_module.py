#!/usr/bin/env python3
"""Package the malachite WPA3 KernelSU module.

Since v2.0 the module ships no binary: wpa3.sh finds and patches the WPA3
version bit in the phone's own wpa_supplicant at install and after ROM
updates. This only zips the scripts, with LF line endings. Anything under
system/ is refused, so a stale patched binary from v1.x can never be shipped.

  python3 tools/make_ksu_module.py --module-dir ksu-module/malachite-wpa3-fix \\
      --out ksu-module/malachite-wpa3-fix-v2.0.zip
"""
import argparse
import hashlib
import os
import sys
import zipfile

TEXT_EXT = {'.sh', '.prop', '.md'}
RESERVED = {'NUL', 'CON', 'PRN', 'AUX'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--module-dir', required=True, help='module directory')
    ap.add_argument('--out', required=True, help='output zip')
    args = ap.parse_args()

    if os.path.exists(os.path.join(args.module_dir, 'system')):
        sys.exit('refusing: %s/system exists; the module builds its overlay on the phone'
                 % args.module_dir)

    if os.path.exists(args.out):
        os.remove(args.out)
    with zipfile.ZipFile(args.out, 'w', zipfile.ZIP_DEFLATED) as z:
        for dirpath, _, files in os.walk(args.module_dir):
            for fn in sorted(files):
                # Git Bash does not treat NUL as a null device, so stray NUL
                # files appear across the tree. Windows resolves them to the
                # device path and they must never enter the module.
                if fn.upper() in RESERVED:
                    continue
                p = os.path.join(dirpath, fn)
                arc = os.path.relpath(p, args.module_dir).replace(os.sep, '/')
                data = open(p, 'rb').read()
                if os.path.splitext(fn)[1] in TEXT_EXT:
                    data = data.replace(b'\r\n', b'\n')
                z.writestr(arc, data)
                print('  %s' % arc)
    zsha = hashlib.sha256(open(args.out, 'rb').read()).hexdigest()
    print('zip    : %s (%d bytes)' % (args.out, os.path.getsize(args.out)))
    print('zip sha: %s' % zsha)


if __name__ == '__main__':
    main()
