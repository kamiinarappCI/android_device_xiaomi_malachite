#!/bin/bash
# Build the Android 17 release tools in the 24.0 tree, then sign and package the
# server-built 24.0 target-files with the release keys.
LOG=$HOME/android/sign24.log
exec >> "$LOG" 2>&1
set -euo pipefail
bash /mnt/e/LineageOS-23.2-Malachite/tools/build_disk.sh up
echo "phase: tools at $(date '+%F %T')"
T=/mnt/wsl/malachite-build/lineage-24
cd "$T"
set +u; source build/envsetup.sh >/dev/null; breakfast malachite user >/dev/null; set -u
[ -n "${SKIP_TOOLS:-}" ] || m sign_target_files_apks ota_from_target_files apksigner signapk delta_generator brillo_update_payload
echo "phase: sign at $(date '+%F %T')"
SRC=/mnt/e/Android/Malachite/builds/server-20261027-24.0
W=$HOME/android/server-20261027-24.0
mkdir -p "$W"
[ -f "$W/lineage_malachite-target_files.zip" ] || cp "$SRC/lineage_malachite-target_files.zip" "$W/"
echo "d7132abbebff4283aac257fba433e1a38aef51d3e5f8dcf71b4815d7fc68819e  $W/lineage_malachite-target_files.zip" | sha256sum -c
export PATH=$T/out/host/linux-x86/bin:$PATH MALACHITE_STATE=$SRC/tree-state.txt MALACHITE_VER=24.0
cd "$W"
ln -sfn "$T/build" build
bash /mnt/e/LineageOS-23.2-Malachite/tools/sign_build.sh "$W/lineage_malachite-target_files.zip"
echo "phase: done at $(date '+%F %T')"
