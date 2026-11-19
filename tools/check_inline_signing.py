#!/usr/bin/env python3
"""Compare the signatures of a new target-files zip with a released one.

    check_inline_signing.py REFERENCE_signed-target_files.zip NEW_target_files.zip

Used by build_malachite.sh before an inline-signed build (setup_inline_keys.sh)
is packaged: a build whose keys differ from the build on the phones would not
dirty-flash over it (apps with changed signatures lose their data or stop
the boot). Exits 1 on any difference that matters:

  1. every APK and APEX container in the images (AOSP's
     check_target_files_signatures -c, run from the build tree)
  2. every APEX payload key (the apex_pubkey inside each .apex/.capex)
  3. mac_permissions.xml: no public AOSP test certificate, same signer set
  4. the APKs that sign_build.sh puts on releasekey inside APEXes
  5. ro.build.tags is release-keys

Known, harmless differences are listed in ALLOWED_PAYLOAD_CHANGES with the
reason. Run with the build environment sourced (check_target_files_signatures
on PATH) from the source root.
"""
import binascii
import glob
import hashlib
import io
import os
import re
import ssl
import subprocess
import sys
import zipfile

# AOSP signs these three vendor APEXes with one shared payload key file
# (hardware/interfaces/apexkey/com.android.hardware.pem); sign_build.sh gave
# each its own key. Inline signing can only provide that one file, so two of
# them get a new payload key. They are pre-installed only: nothing updates
# them from /data, where apexd would require the old key.
ALLOWED_PAYLOAD_CHANGES = {
    "com.android.hardware.cas",
    "com.android.hardware.drm.clearkey",
    "com.android.hardware.boot",
}

APEX_APKS = """com.android.appsearch.apk AdServicesApk FederatedCompute HalfSheetUX
HealthConnectBackupRestore HealthConnectController OsuLogin SafetyCenterResources
ServiceConnectivityResources ServiceUwbResources ServiceWifiResources
TelecomServiceResources TelecomUi WebAppService WifiDialog""".split()

IMAGE_DIRS = ("SYSTEM/", "SYSTEM_EXT/", "PRODUCT/", "VENDOR/", "ODM/",
              "VENDOR_DLKM/", "ODM_DLKM/", "SYSTEM_DLKM/")


def apex_payload_keys(tf):
    """{apex file name: sha256 of its apex_pubkey} for every APEX in the images."""
    keys = {}
    for name in tf.namelist():
        if not name.startswith(IMAGE_DIRS) or not name.endswith((".apex", ".capex")):
            continue
        with zipfile.ZipFile(io.BytesIO(tf.read(name))) as apex:
            if "apex_pubkey" in apex.namelist():
                pub = apex.read("apex_pubkey")
            elif "original_apex" in apex.namelist():  # compressed APEX
                with zipfile.ZipFile(io.BytesIO(apex.read("original_apex"))) as inner:
                    pub = inner.read("apex_pubkey")
            else:
                continue
        keys[os.path.basename(name)] = hashlib.sha256(pub).hexdigest()
    return keys


def mac_signatures(tf):
    sigs = {}
    for name in tf.namelist():
        if name.endswith("mac_permissions.xml"):
            xml = tf.read(name).decode()
            for sig, info in re.findall(
                    r'signature="([0-9a-fA-F]+)"\s*>\s*<seinfo value="([^"]+)"', xml):
                sigs[(name, info)] = sig.lower()
    return sigs


def test_certs(top):
    certs = {}
    for pem in glob.glob(os.path.join(top, "build/make/target/product/security/*.x509.pem")):
        der = ssl.PEM_cert_to_DER_cert(open(pem).read())
        certs[binascii.hexlify(der).decode()] = os.path.basename(pem)
    return certs


def build_tags(tf):
    for name in ("SYSTEM/build.prop", "SYSTEM/system/build.prop"):
        if name in tf.namelist():
            m = re.search(r"^ro\.build\.tags=(.*)$", tf.read(name).decode(), re.M)
            if m:
                return m.group(1)
    return None


def apkcerts(tf):
    certs = {}
    for line in tf.read("META/apkcerts.txt").decode().splitlines():
        m = re.match(r'name="([^"]+)" certificate="([^"]+)"', line)
        if m:
            certs[m.group(1)] = m.group(2)
    return certs


def main(ref_path, new_path):
    top = os.getcwd()
    problems = []

    print("APK and APEX container signatures (check_target_files_signatures):")
    run = subprocess.run(["check_target_files_signatures", "-c", ref_path, new_path],
                         capture_output=True, text=True)
    out = run.stdout + run.stderr
    if "some APKs changed certs" in out:
        section = out.split("APK signing differences", 1)[-1]
        print(section.strip()[:6000])
        problems.append("APKs or APEX containers changed certificates")
    elif "Traceback" in out or ("problem(s) found" not in out and run.returncode != 0):
        print(out[-3000:])
        problems.append("check_target_files_signatures failed to run")
    else:
        print("  same certificates in both builds")

    with zipfile.ZipFile(ref_path) as ref, zipfile.ZipFile(new_path) as new:
        print("APEX payload keys:")
        old_keys, new_keys = apex_payload_keys(ref), apex_payload_keys(new)
        changed = sorted(a for a in new_keys if a in old_keys and old_keys[a] != new_keys[a])
        for apex in changed:
            stem = re.sub(r"\.c?apex$", "", apex)
            if stem in ALLOWED_PAYLOAD_CHANGES:
                print(f"  allowed: {apex} (shared AOSP payload key file, pre-installed only)")
            else:
                print(f"  CHANGED: {apex}")
                problems.append(f"APEX payload key changed: {apex}")
        if not changed:
            print(f"  all {len(new_keys)} unchanged")

        print("mac_permissions signers:")
        tests = test_certs(top)
        new_sigs, old_sigs = mac_signatures(new), mac_signatures(ref)
        for (name, info), sig in sorted(new_sigs.items()):
            if sig in tests:
                problems.append(f"{name}: seinfo {info} is the AOSP test key {tests[sig]}")
            elif (name, info) in old_sigs and old_sigs[(name, info)] != sig:
                problems.append(f"{name}: seinfo {info} has a different signer than the reference")
        print("  " + ("ok" if not any("seinfo" in p for p in problems) else "differences above"))

        print("APKs inside APEXes on releasekey:")
        certs = apkcerts(new)
        for apk in APEX_APKS:
            cert = certs.get(apk + ".apk")
            if cert and not cert.endswith("vendor/lineage-priv/keys/releasekey.x509.pem"):
                problems.append(f"{apk}.apk inside its APEX is signed with {cert}")
        print("  " + ("ok" if not any("inside its APEX" in p for p in problems) else "differences above"))

        tags = build_tags(new)
        print(f"ro.build.tags: {tags}")
        if tags != "release-keys":
            problems.append(f"ro.build.tags is {tags}, not release-keys")

    if problems:
        print(f"\n{len(problems)} problem(s): do not flash this build over the reference")
        for p in problems:
            print("  " + p)
        return 1
    print("\nsignatures match the reference")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
