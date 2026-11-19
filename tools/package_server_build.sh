#!/usr/bin/env bash
# Turn a server_run.sh result folder into a release-style test folder, like the earlier
# ones: ROM zip, boot.img, init_boot.img, vendor_boot.img, MindTheGapps (ROMs without
# Google apps), FLASHING.md, SHA256SUMS.txt and tree-state.txt. The logs move to
# builds/_logs/<folder>.
#
#   bash tools/package_server_build.sh lineage|evox|crdroid <server_run result folder> <yyyymmdd>
set -euo pipefail
ROM=${1:?rom}; SRC=${2:?result folder}; DATE=${3:?yyyymmdd}
B=/e/Android/Malachite/builds
# Templates: the newest folder of each ROM and the date written in it.
TPL_LOS=$B/20261031-24.0-release-test; TD_LOS=20261031
TPL_EVO=$B/EvolutionX-cnb-20261030-gapps-test; TD_EVO=20261030
MTG=$(cd "$TPL_LOS" && ls MindTheGapps-*.zip | head -1)
case $ROM in
  lineage) DIR=$DATE-24.0-release-test; ZIP=lineage-24.0-$DATE-UNOFFICIAL-malachite-test.zip; GAPPS=1
    sed "s/$TD_LOS/$DATE/g" "$TPL_LOS/FLASHING.md" > "$SRC/FLASHING.md" ;;
  evox) DIR=EvolutionX-cnb-$DATE-gapps-test; ZIP=EvolutionX-cnb-$DATE-UNOFFICIAL-malachite-gapps-test.zip; GAPPS=0
    sed "s/$TD_EVO/$DATE/g" "$TPL_EVO/FLASHING.md" > "$SRC/FLASHING.md" ;;
  crdroid) DIR=crDroid-17.0-$DATE-test; ZIP=crDroid-17.0-$DATE-UNOFFICIAL-malachite-test.zip; GAPPS=1
    sed -e "s/lineage-24.0-$TD_LOS-UNOFFICIAL-malachite-test.zip/$ZIP/g" -e "s/$TD_LOS/$DATE/g" \
        -e "s/^# Flashing LineageOS 24.0 /# Flashing crDroid 17.0 /" \
        -e "s/In LineageOS recovery:/In the recovery:/" \
        -e "s/Update over LineageOS 23.2 or an earlier 24.0 build/Update over LineageOS 23.2 or an earlier crDroid 17.0 build/" \
        -e "s/^Android 16 package\.$/Android 16 package, and remove any enrolled face on 23.2 first: crDroid uses a different\nface service.\n\nComing from any other ROM, do a clean install (A)./" \
        "$TPL_LOS/FLASHING.md" > "$SRC/FLASHING.md" ;;
  *) echo "unknown rom $ROM"; exit 1 ;;
esac
[ -e "$B/$DIR" ] && { echo "$B/$DIR already exists"; exit 1; }
cd "$SRC"
for f in signed-ota_update.zip boot.img init_boot.img vendor_boot.img; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
mv signed-ota_update.zip "$ZIP"
[ $GAPPS = 1 ] && cp "$TPL_LOS/$MTG" .
mkdir -p "$B/_logs/$DIR"
for f in build.log errors.txt ota.log sign.out keys-cleanup.log images.sha256; do [ -e "$f" ] && mv "$f" "$B/_logs/$DIR/"; done
files="$ZIP boot.img init_boot.img vendor_boot.img"; [ $GAPPS = 1 ] && files="$MTG $files"
sha256sum $files > SHA256SUMS.txt
cd "$B" && mv "$SRC" "$DIR"
echo "$B/$DIR:"; ls "$B/$DIR"
