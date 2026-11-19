#!/bin/bash
# Companion of server_build24.sh for inline-signed server builds: waits for the
# build to end, makes the signed OTA with the release key, then deletes the keys
# and every copy of them the build made (otatools.zip bundles the signing keys;
# anything in out/ or the work folder with a key's checksum goes too). Runs even
# when the build fails, so the keys never stay behind.
#
#   ssh <server> 'nohup setsid bash malachite-24/server_sign24.sh >/dev/null 2>&1 &'
W=${W:-$HOME/malachite-24}
T=${T:-$W/lineage-24}
K=$T/vendor/lineage-priv
LOG=$W/build.log
until grep -q "^build exit" "$LOG" 2>/dev/null; do sleep 20; done
cd "$T" || exit 1
if grep -q "^build exit: 0" "$LOG" && [ -f "$W/lineage_malachite-target_files.zip" ]; then
  echo "phase: signed OTA at $(date '+%F %T')" >> "$LOG"
  export PATH=$T/out/host/linux-x86/bin:$PATH
  # Give the extracted target files, as the build's own otapackage does: crDroid's
  # releasetools find partitions only in a folder and fail on the zip (KeyError: 'system').
  IN=$W/lineage_malachite-target_files.zip
  D=$T/out/target/product/malachite/obj/PACKAGING/target_files_intermediates/lineage_malachite-target_files
  [ -d "$D" ] && IN=$D
  if ota_from_target_files -k "$K/keys/releasekey" --block --backup=true \
      "$IN" "$W/signed-ota_update.zip" > "$W/ota.log" 2>&1; then
    (cd "$W" && sha256sum signed-ota_update.zip lineage_malachite-target_files.zip > SHA256SUMS.txt)
    echo "ota: ok $(cut -c1-16 "$W/SHA256SUMS.txt" | head -1)" >> "$LOG"
  else
    echo "ota: FAILED (see ota.log)" >> "$LOG"
  fi
fi
# Delete the keys and every copy of them.
sums=$(find "$K" -type f \( -name "*.pk8" -o -name "*.pem" \) -exec sha256sum {} + | cut -c1-64 | sort -u)
rm -f "$T"/out/target/product/malachite/otatools.zip
find "$T/out" "$W" -path "$K" -prune -o -type f \( -name "*.pk8" -o -name "*.pem" \) -print0 2>/dev/null |
  xargs -0 -r sha256sum 2>/dev/null | while read -r s f; do
    grep -qx "$s" <<<"$sums" && { shred -u "$f"; echo "deleted copy $f" >> "$W/keys-cleanup.log"; }
  done
find "$K" -type f -exec shred -u {} +
rm -rf "$K"
left=$(find "$T" "$W" -type f \( -name "*.pk8" -o -name "*.pem" \) -print0 2>/dev/null | xargs -0 -r sha256sum 2>/dev/null |
  cut -c1-64 | grep -cxF "$sums")
echo "keys deleted at $(date '+%F %T'), copies left: $left" >> "$LOG"
