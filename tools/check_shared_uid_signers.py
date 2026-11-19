#!/usr/bin/env python3
"""Check a signed target-files zip for shared UIDs with mixed signers.

On a dirty flash with new keys, LineageOS 23.2 accepts a preinstalled app
whose signature changed, but throws in system_server (bootloop) when the
preinstalled members of one shared UID end up with different signers
(ReconcilePackageUtils; malachite launched on API 34). This lists every
preinstalled APK's sharedUserId, read from its binary manifest, including
APKs inside APEXes, and the certificate that actually signed it (SHA-256
digest from apksigner, so PRESIGNED apps count as their real signer).

    source build/envsetup.sh   # puts apksigner and deapexer on PATH
    python3 tools/check_shared_uid_signers.py signed-target_files.zip

Exit status 0 = every shared UID has one signer, 1 = mixed signers found,
2 = something could not be checked (unreadable manifest, apksigner or
deapexer missing or failing). Only 0 is a pass.

--trust-apkcerts uses META/apkcerts.txt instead of apksigner (each PRESIGNED
APK then counts as its own signer), --skip-apex skips APEX contents; both
weaken the check and are meant for tests.
"""
from __future__ import annotations

import argparse
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from collections import defaultdict

ANDROID_NS = "http://schemas.android.com/apk/res/android"

# Top-level directories of target-files that hold preinstalled partitions.
PARTITIONS = ("SYSTEM/", "SYSTEM_EXT/", "PRODUCT/", "VENDOR/", "ODM/")


def _string_pool(data: bytes, off: int) -> list[str]:
    _, header_size, _ = struct.unpack_from("<HHI", data, off)
    count, _, flags, strings_start, _ = struct.unpack_from("<IIIII", data, off + 8)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from(f"<{count}I", data, off + header_size)
    base = off + strings_start
    out = []
    for o in offsets:
        p = base + o
        if utf8:
            n = data[p]
            p += 2 if n & 0x80 else 1  # UTF-16 length, skipped
            n = data[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[p + 1]
                p += 2
            else:
                p += 1
            out.append(data[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, p)[0]
            p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, p)[0]
                p += 2
            out.append(data[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out


def manifest_attrs(axml: bytes) -> dict[str, str]:
    """package and sharedUserId from a compiled AndroidManifest.xml."""
    kind, header_size, total = struct.unpack_from("<HHI", axml, 0)
    if kind != 0x0003:
        raise ValueError("not a binary XML file")
    strings: list[str] = []
    off = header_size
    while off < total:
        ctype, chdr, csize = struct.unpack_from("<HHI", axml, off)
        if ctype == 0x0001:
            strings = _string_pool(axml, off)
        elif ctype == 0x0102:  # start element
            name_idx = struct.unpack_from("<I", axml, off + 20)[0]
            if strings[name_idx] == "manifest":
                attr_start, attr_size, attr_count = struct.unpack_from("<HHH", axml, off + 24)
                result = {}
                for i in range(attr_count):
                    a = off + 16 + attr_start + i * attr_size
                    ns, name, raw = struct.unpack_from("<iii", axml, a)
                    if raw < 0:
                        continue
                    key = strings[name]
                    if key in ("package", "sharedUserId"):
                        result[key] = strings[raw]
                return result
        off += csize
    return {}


def apkcerts(zf: zipfile.ZipFile) -> dict[str, str]:
    certs = {}
    for line in zf.read("META/apkcerts.txt").decode().splitlines():
        m = re.search(r'name="([^"]+)" certificate="([^"]*)"', line)
        if m:
            certs[m.group(1)] = m.group(2)
    return certs


def apksigner_digest(apksigner: str, apk_bytes: bytes) -> str:
    """SHA-256 digest(s) of the certificate(s) that signed an APK."""
    with tempfile.NamedTemporaryFile(suffix=".apk", delete=False) as f:
        f.write(apk_bytes)
        path = f.name
    try:
        r = subprocess.run([apksigner, "verify", "--print-certs", path],
                           capture_output=True, text=True)
    finally:
        os.unlink(path)
    digests = re.findall(r"certificate SHA-256 digest: ([0-9a-f]+)", r.stdout)
    if r.returncode != 0 or not digests:
        raise ValueError(f"apksigner failed: {(r.stderr or r.stdout).strip()[:200]}")
    return "sha256:" + "+".join(sorted(set(d[:16] for d in digests)))


def apex_apks(deapexer: str, apex_bytes: bytes, name: str):
    """Yield (path, bytes) for every APK inside an .apex or .capex."""
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, name)
        with open(src, "wb") as f:
            f.write(apex_bytes)
        tools = []
        for flag, tool in (("--debugfs_path", "debugfs_static"), ("--fsckerofs_path", "fsck.erofs")):
            found = shutil.which(tool)
            if found:
                tools += [flag, found]
        if name.endswith(".capex"):
            plain = os.path.join(d, "decompressed.apex")
            subprocess.run([deapexer] + tools + ["decompress", "--input", src, "--output", plain],
                           check=True, capture_output=True)
            src = plain
        out = os.path.join(d, "out")
        subprocess.run([deapexer] + tools + ["extract", src, out], check=True, capture_output=True)
        for root, _, files in os.walk(out):
            for f in files:
                if f.endswith(".apk"):
                    p = os.path.join(root, f)
                    with open(p, "rb") as fh:
                        yield os.path.relpath(p, out), fh.read()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("target_files")
    ap.add_argument("-v", "--verbose", action="store_true", help="list every member")
    ap.add_argument("--apksigner", default=shutil.which("apksigner"))
    ap.add_argument("--deapexer", default=shutil.which("deapexer"))
    ap.add_argument("--trust-apkcerts", action="store_true",
                    help="use META/apkcerts.txt instead of apksigner (tests)")
    ap.add_argument("--skip-apex", action="store_true", help="do not look inside APEXes (tests)")
    args = ap.parse_args()

    if not args.trust_apkcerts and not args.apksigner:
        print("ERROR  apksigner not found; source build/envsetup.sh or pass --apksigner")
        return 2
    if not args.skip_apex and not args.deapexer:
        print("ERROR  deapexer not found; build otatools or pass --deapexer")
        return 2

    zf = zipfile.ZipFile(args.target_files)
    certs = apkcerts(zf)
    groups: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    problems = []
    scanned = 0

    def signer(name: str, entry: str, data: bytes) -> str:
        if args.trust_apkcerts:
            cert = certs.get(name, "NOT IN apkcerts.txt")
            return f"PRESIGNED:{entry}" if cert == "PRESIGNED" else cert
        return apksigner_digest(args.apksigner, data)

    def consider(entry: str, data: bytes) -> None:
        nonlocal scanned
        scanned += 1
        name = entry.rsplit("/", 1)[1]
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as apk:
                attrs = manifest_attrs(apk.read("AndroidManifest.xml"))
            uid = attrs.get("sharedUserId")
            if uid:
                groups[uid].append((name, signer(name, entry, data), entry))
        except Exception as e:  # corrupt APK, unparsable manifest, apksigner failure
            problems.append(f"{entry}: {e}")

    for entry in zf.namelist():
        if not entry.startswith(PARTITIONS):
            continue
        if entry.endswith(".apk"):
            consider(entry, zf.read(entry))
        elif entry.endswith((".apex", ".capex")) and not args.skip_apex:
            try:
                for inner, data in apex_apks(args.deapexer, zf.read(entry),
                                             entry.rsplit("/", 1)[1]):
                    consider(f"{entry}!/{inner}", data)
            except Exception as e:
                problems.append(f"{entry}: deapexer failed: {e}")

    bad = 0
    for uid in sorted(groups):
        members = groups[uid]
        signers = {c for _, c, _ in members}
        mixed = len(signers) > 1
        bad += mixed
        print(f"{'MIXED' if mixed else 'ok   '}  {uid}  ({len(members)} apps, "
              f"signer{'s' if mixed else ''}: {', '.join(sorted(signers))})")
        if mixed or args.verbose:
            for name, cert, entry in sorted(members):
                print(f"         {cert:50}  {entry}")
    for p in problems:
        print(f"ERROR  could not check: {p}")
    print(f"\n{scanned} APKs scanned, {len(groups)} shared UIDs, {bad} with mixed signers, "
          f"{len(problems)} not checked.")
    if bad:
        return 1
    return 2 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
