#!/usr/bin/env bash
# Re-sign a malachite target-files zip with our keys and make the flashable
# OTA (package_build.sh). Only for builds without inline signing:
# build_malachite.sh skips this when vendor/lineage-priv/keys/keys.mk exists
# (setup_inline_keys.sh), which saves the ~19 minutes this takes.
# Run from the LineageOS source root after `mka target-files-package otatools`
# (and `source build/envsetup.sh`, which puts the releasetools on PATH):
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/sign_build.sh [target-files.zip]
#
# The APEX list comes from this build's META/apexkeys.txt, so no module is
# left on test keys. Output: signed-target_files.zip, signed-ota_update.zip.
set -euo pipefail

CERTS=${CERTS:-$HOME/.android-certs}
TF=${1:-$(ls -t "$OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)}
echo "Target files: $TF"

# APKs shipped inside APEXes; the wiki signs them with releasekey.
APEX_APKS="com.android.appsearch.apk AdServicesApk FederatedCompute HalfSheetUX
HealthConnectBackupRestore HealthConnectController OsuLogin SafetyCenterResources
ServiceConnectivityResources ServiceUwbResources ServiceWifiResources
TelecomServiceResources TelecomUi WebAppService WifiDialog"

args=()
missing=0
apkcerts=$(unzip -p "$TF" META/apkcerts.txt)
for apk in $APEX_APKS; do
  apk=${apk%.apk}.apk
  if grep -q "name=\"$apk\"" <<<"$apkcerts"; then
    args+=(--extra_apks "$apk=$CERTS/releasekey")
  fi
done

# The NFC app inside com.android.nfcservices uses the nfc certificate, which
# -d does not map (only testkey, devkey, media, shared, platform,
# networkstack, sdk_sandbox, bluetooth); without this it keeps the public
# AOSP test key. Map the key, not the APK: only key mappings also replace
# the certificate in mac_permissions.xml. Re-signing the APK alone (2026-09-28
# build) left its seinfo "nfc" entry on the test key, so zygote could not
# label com.android.nfc and NFC never started.
args+=(-k "build/make/target/product/security/nfc=$CERTS/nfc")

while read -r line; do
  name=$(sed -n 's/^name="\([^"]*\.apex\)".*/\1/p' <<<"$line")
  [[ -n $name ]] || continue
  if grep -q 'container_certificate="PRESIGNED"' <<<"$line"; then
    continue
  fi
  key=${name%.apex}
  if [[ ! -f $CERTS/$key.pk8 || ! -f $CERTS/$key.pem ]]; then
    echo "missing key: $CERTS/$key (run make_keys.sh with this target-files zip)" >&2
    missing=1
    continue
  fi
  args+=(--extra_apks "$name=$CERTS/$key" --extra_apex_payload_key "$name=$CERTS/$key.pem")
done < <(unzip -p "$TF" META/apexkeys.txt)
[[ $missing == 0 ]] || exit 1

sign_target_files_apks -o -d "$CERTS" "${args[@]}" "$TF" signed-target_files.zip

# Every signer in the SELinux mac_permissions files must be one of our keys.
# A public AOSP test certificate left there means an app signed with our key
# gets seinfo "default" and may not start.
echo "mac_permissions signer check:"
python3 - signed-target_files.zip build/make/target/product/security <<'PY'
import binascii, glob, re, ssl, sys, zipfile
test = {}
for pem in glob.glob(sys.argv[2] + "/*.x509.pem"):
    der = ssl.PEM_cert_to_DER_cert(open(pem).read())
    test[binascii.hexlify(der).decode()] = pem
bad = 0
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        if not name.endswith("mac_permissions.xml"):
            continue
        xml = z.read(name).decode()
        for sig, info in re.findall(r'signature="([0-9a-fA-F]+)"\s*>\s*<seinfo value="([^"]+)"', xml):
            if sig.lower() in test:
                print(f"  TEST KEY  {name}: seinfo {info} = {test[sig.lower()]}")
                bad = 1
sys.exit(bad)
PY
echo "  ok"

bash "$(dirname "$0")/package_build.sh" signed-target_files.zip "$CERTS/releasekey"
