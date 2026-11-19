"""Tests for check_shared_uid_signers.py, using hand-built binary manifests."""
import io
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_shared_uid_signers as checker  # noqa: E402


def axml(package: str, shared_uid: str | None, utf8: bool = False) -> bytes:
    """A minimal compiled AndroidManifest.xml: <manifest package= sharedUserId=>."""
    strings = ["manifest", "package", "sharedUserId", checker.ANDROID_NS, package,
               shared_uid or ""]
    data = b""
    offsets = []
    for s in strings:
        offsets.append(len(data))
        if utf8:
            b = s.encode()
            data += bytes([len(s), len(b)]) + b + b"\0"
        else:
            data += struct.pack("<H", len(s)) + s.encode("utf-16-le") + b"\0\0"
    data += b"\0" * (-len(data) % 4)
    hdr = 28
    pool = struct.pack("<HHIIIIII", 0x0001, hdr, hdr + 4 * len(strings) + len(data),
                       len(strings), 0, 0x100 if utf8 else 0, hdr + 4 * len(strings), 0)
    pool += struct.pack(f"<{len(strings)}I", *offsets) + data

    attrs = [(-1, 1, 4)]  # package (no namespace)
    if shared_uid:
        attrs.append((3, 2, 5))
    body = b"".join(struct.pack("<iiiHBBi", ns, name, raw, 8, 0, 3, raw)
                    for ns, name, raw in attrs)
    elem = struct.pack("<HHIIiiiHHHHHH", 0x0102, 16, 36 + len(body), 1, -1,
                       -1, 0, 20, 20, len(attrs), 0, 0, 0) + body
    total = 8 + len(pool) + len(elem)
    return struct.pack("<HHI", 0x0003, 8, total) + pool + elem


def apk(manifest: bytes) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("AndroidManifest.xml", manifest)
    return buf.getvalue()


class ManifestTests(unittest.TestCase):
    def test_utf16_and_utf8_pools(self):
        for utf8 in (False, True):
            self.assertEqual(
                checker.manifest_attrs(axml("com.android.settings", "android.uid.system", utf8)),
                {"package": "com.android.settings", "sharedUserId": "android.uid.system"})

    def test_no_shared_uid(self):
        self.assertEqual(checker.manifest_attrs(axml("com.x", None)), {"package": "com.x"})


class TargetFilesTests(unittest.TestCase):
    def run_checker(self, members, extra=None, flags=("--trust-apkcerts", "--skip-apex")):
        with tempfile.TemporaryDirectory() as d:
            tf = Path(d) / "tf.zip"
            with zipfile.ZipFile(tf, "w") as z:
                for path, data in (extra or {}).items():
                    z.writestr(path, data)
                lines = []
                for path, uid, cert in members:
                    z.writestr(path, apk(axml("p." + path.rsplit("/", 1)[1], uid)))
                    lines.append(f'name="{path.rsplit("/", 1)[1]}" certificate="{cert}" '
                                 f'private_key="" partition="system"')
                z.writestr("META/apkcerts.txt", "\n".join(lines) + "\n")
            r = subprocess.run([sys.executable, str(HERE / "check_shared_uid_signers.py"),
                                str(tf), *flags], capture_output=True, text=True)
            return r.returncode, r.stdout

    def test_consistent_groups_pass(self):
        code, out = self.run_checker([
            ("SYSTEM/system/framework/framework-res.apk", "android.uid.system", "k/platform"),
            ("SYSTEM_EXT/priv-app/Settings/Settings.apk", "android.uid.system", "k/platform"),
            ("PRODUCT/app/Other/Other.apk", None, "PRESIGNED"),
        ])
        self.assertEqual(code, 0, out)
        self.assertIn("ok     android.uid.system  (2 apps", out)

    def test_presigned_member_in_system_uid_fails(self):
        code, out = self.run_checker([
            ("SYSTEM/system/framework/framework-res.apk", "android.uid.system", "k/platform"),
            ("VENDOR/app/Xiaomi/Xiaomi.apk", "android.uid.system", "PRESIGNED"),
        ])
        self.assertEqual(code, 1, out)
        self.assertIn("MIXED  android.uid.system", out)
        self.assertIn("VENDOR/app/Xiaomi/Xiaomi.apk", out)

    def test_two_different_presigned_members_fail(self):
        code, out = self.run_checker([
            ("VENDOR/app/A/A.apk", "android.uid.phone", "PRESIGNED"),
            ("ODM/app/B/B.apk", "android.uid.phone", "PRESIGNED"),
        ])
        self.assertEqual(code, 1, out)
        self.assertIn("MIXED  android.uid.phone", out)

    def test_unreadable_manifest_is_not_a_pass(self):
        code, out = self.run_checker(
            [("SYSTEM/system/framework/framework-res.apk", "android.uid.system", "k/platform")],
            extra={"SYSTEM/app/Broken/Broken.apk": b"not a zip"})
        self.assertEqual(code, 2, out)
        self.assertIn("could not check: SYSTEM/app/Broken/Broken.apk", out)

    def test_missing_tools_are_not_a_pass(self):
        code, out = self.run_checker(
            [("SYSTEM/system/framework/framework-res.apk", "android.uid.system", "k/platform")],
            flags=("--apksigner", "", "--deapexer", ""))
        self.assertEqual(code, 2, out)


if __name__ == "__main__":
    unittest.main()
