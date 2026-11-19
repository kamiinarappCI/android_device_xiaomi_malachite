#!/usr/bin/env bash
# Make the flashable OTA from a signed target-files zip and archive it. Run
# from the LineageOS source root with the build environment sourced; called
# by build_malachite.sh (inline-signed builds) and sign_build.sh (re-signed
# builds):
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/package_build.sh <signed target-files.zip> <signing key>
#
# Archives under a normal ROM name, like official LineageOS zips:
# lineage-23.2-<date>-UNOFFICIAL-malachite[-diagnostic][-test].zip in
# ~/android/releases/<dir>/ and E:\Android\Malachite\builds\<dir>\. "-test"
# marks a build of lineage-23.2 plus feature branches (prepare_tree.sh), which
# is for testing only; only builds of plain lineage-23.2 are releases.
# MALACHITE_VER=24.0 (another LineageOS version's tree) names the zip after it
# and always makes a test build, so the 23.2 signature reference stays put.
set -euo pipefail
TF=$1
KEY=$2
TOOLS=$(dirname "$0")
# A build made on another machine passes its own tree state.
STATE=${MALACHITE_STATE:-$HOME/android/tree-state.txt}
VER=${MALACHITE_VER:-23.2}

ota_from_target_files -k "$KEY" --block --backup=true "$TF" signed-ota_update.zip

# Inline-signed builds: build_malachite.sh runs check_inline_signing.py beside
# the OTA generation (CHECK_PID, CHECK_LOG). Archive only if it passed.
if [[ -n ${CHECK_PID:-} ]]; then
  while kill -0 "$CHECK_PID" 2>/dev/null; do sleep 5; done
  echo
  echo "Signature check against the reference release:"
  cat "$CHECK_LOG"
  if ! grep -q '^signatures match the reference$' "$CHECK_LOG"; then
    rm -f signed-ota_update.zip
    echo "FAILED: signatures differ from the reference release; OTA deleted"
    exit 1
  fi
fi

echo
echo "Shared-UID signer check:"
python3 "$TOOLS/check_shared_uid_signers.py" "$TF"
sha256sum signed-ota_update.zip

# build_malachite.sh keeps WITH_ADB_INSECURE only for diagnostic builds.
if [[ -n ${WITH_ADB_INSECURE:-} ]]; then type=diagnostic
else type=release; fi
branches=
[[ -f $STATE ]] && branches=$(sed -n 's/^# branches: //p' "$STATE")
test=; [[ -n $branches || $VER != 23.2 ]] && test=-test
day=$(date +%Y%m%d)
pre=$day; [[ $VER != 23.2 ]] && pre=$day-$VER
# MALACHITE_ROM=crdroid (build_crdroid.sh): crDroid-17.0-<day>[-n]-test, the name
# the 2026-10-31 crDroid release used.
[[ ${MALACHITE_ROM:-} == crdroid ]] && pre=crDroid-$VER-$day
dir=$pre-$type$test; n=2
[[ ${MALACHITE_ROM:-} == crdroid && $type == release ]] && dir=$pre$test
while [[ -e $HOME/android/releases/$dir ]]; do dir=$pre-$n-$type$test; n=$((n + 1)); done
suffix=-$type; [[ $type == release ]] && suffix=
zip=lineage-$VER-$day-UNOFFICIAL-malachite$suffix$test.zip
[[ ${MALACHITE_ROM:-} == crdroid ]] && zip=crDroid-$VER-$day-UNOFFICIAL-malachite$suffix$test.zip
win=/mnt/e/Android/Malachite/builds/$dir
mkdir -p "$HOME/android/releases/$dir" "$win"
cp signed-ota_update.zip "$HOME/android/releases/$dir/$zip"
(cd "$HOME/android/releases/$dir" && sha256sum "$zip" > "$zip.sha256")
[[ -f $STATE ]] && cp "$STATE" "$HOME/android/releases/$dir/tree-state.txt"
# Only release builds keep their signed target-files: the newest one is the
# reference check_inline_signing.py compares the next build with.
if [[ $type == release && -z $test ]]; then
  cp "$TF" "$HOME/android/releases/$dir/signed-target_files.zip"
fi
cp "$HOME/android/releases/$dir/$zip" "$HOME/android/releases/$dir/$zip.sha256" "$win/"
[[ -f $STATE ]] && cp "$STATE" "$win/tree-state.txt"
(cd "$win" && sha256sum -c "$zip.sha256" >/dev/null) || { echo "copy to E: failed checksum"; exit 1; }
# A release folder also carries the boot images for root and recovery, with
# one SHA256SUMS.txt instead of the per-zip checksum. MindTheGapps, the banner
# and FLASHING.md are added by hand.
if [[ $type == release && -z $test ]]; then
  unzip -q -o -j "$TF" IMAGES/boot.img IMAGES/init_boot.img IMAGES/vendor_boot.img -d "$win"
  (cd "$win" && rm -f "$zip.sha256" && sha256sum -- *.zip *.img > SHA256SUMS.txt)
fi
echo "READY: E:\\Android\\Malachite\\builds\\$dir\\$zip"
