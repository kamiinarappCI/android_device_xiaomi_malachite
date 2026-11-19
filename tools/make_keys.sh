#!/usr/bin/env bash
# Create our signing keys (no password), following the LineageOS wiki
# "Signing builds". Run from the LineageOS source root:
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/make_keys.sh                 # standard + wiki APEX list
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/make_keys.sh target-files.zip # + any APEX that build has
#
# Never overwrites an existing key: new keys would need another migration.
# Keep an offline copy of ~/.android-certs.
set -euo pipefail

CERTS=${CERTS:-$HOME/.android-certs}
SUBJECT='/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'
MAKE_KEY=${MAKE_KEY:-./development/tools/make_key}
[[ -x $MAKE_KEY ]] || { echo "run from the LineageOS source root, or set MAKE_KEY" >&2; exit 1; }
mkdir -p "$CERTS"
chmod 700 "$CERTS"

made=0
for cert in bluetooth cyngn-app media networkstack nfc platform releasekey sdk_sandbox shared testcert verity; do
  [[ -f $CERTS/$cert.pk8 ]] && continue
  yes "" | "$MAKE_KEY" "$CERTS/$cert" "$SUBJECT" >/dev/null 2>&1 || true
  [[ -f $CERTS/$cert.pk8 ]] || { echo "failed: $cert" >&2; exit 1; }
  made=$((made + 1))
done
ln -sf releasekey.pk8 "$CERTS/testkey.pk8"
ln -sf releasekey.x509.pem "$CERTS/testkey.x509.pem"

# APEX keys must be SHA256_RSA4096.
sed 's|2048|4096|g' "$MAKE_KEY" > "$CERTS/make_key"
chmod +x "$CERTS/make_key"

apexes="com.android.adbd com.android.adservices com.android.adservices.api com.android.appsearch
com.android.art com.android.bluetooth com.android.bt com.android.btservices com.android.cellbroadcast
com.android.compos com.android.configinfrastructure com.android.connectivity.resources
com.android.conscrypt com.android.crashrecovery com.android.devicelock com.android.extservices
com.android.graphics.pdf com.android.hardware.authsecret com.android.hardware.biometrics.face.virtual
com.android.hardware.biometrics.fingerprint.virtual com.android.hardware.boot com.android.hardware.cas
com.android.hardware.contexthub com.android.hardware.drm.clearkey com.android.hardware.dumpstate
com.android.hardware.gatekeeper.nonsecure com.android.hardware.neuralnetworks
com.android.hardware.power com.android.hardware.rebootescrow com.android.hardware.thermal
com.android.hardware.threadnetwork com.android.hardware.uwb com.android.hardware.vibrator
com.android.hardware.wifi com.android.healthfitness com.android.hotspot2.osulogin com.android.i18n
com.android.ipsec com.android.media com.android.media.swcodec com.android.mediaprovider
com.android.nearby.halfsheet com.android.networkstack.tethering com.android.neuralnetworks
com.android.nfcservices com.android.npumanager com.android.ondevicepersonalization
com.android.os.statsd com.android.permission com.android.profiling com.android.resolv com.android.rkpd
com.android.runtime com.android.safetycenter.resources com.android.scheduling com.android.sdkext
com.android.support.apexer com.android.telephony com.android.telephonycore
com.android.telephonymodules com.android.tethering com.android.tzdata com.android.uprobestats
com.android.uwb com.android.uwb.resources com.android.virt com.android.vndk.current
com.android.vndk.current.on_vendor com.android.webapp com.android.wifi com.android.wifi.dialog
com.android.wifi.resources com.google.pixel.camera.hal com.google.pixel.vibrator.hal com.qorvo.uwb"
if [[ $# -ge 1 ]]; then
  apexes="$apexes $(unzip -p "$1" META/apexkeys.txt \
    | grep -v 'container_certificate="PRESIGNED"' \
    | sed -n 's/^name="\([^"]*\)\.apex".*/\1/p')"
fi

for apex in $(tr ' ' '\n' <<<"$apexes" | sort -u); do
  [[ -f $CERTS/$apex.pem ]] && continue
  subject="/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=$apex/emailAddress=android@android.com"
  if [[ ! -f $CERTS/$apex.pk8 ]]; then
    yes "" | "$CERTS/make_key" "$CERTS/$apex" "$subject" >/dev/null 2>&1 || true
  fi
  [[ -f $CERTS/$apex.pk8 ]] || { echo "failed: $apex" >&2; exit 1; }
  openssl pkcs8 -in "$CERTS/$apex.pk8" -inform DER -nocrypt -out "$CERTS/$apex.pem"
  made=$((made + 1))
done

echo "Created $made keys in $CERTS ($(ls "$CERTS"/*.pk8 | wc -l) total). Back this folder up offline."
