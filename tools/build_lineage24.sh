#!/bin/bash
# LineageOS 24.0 (Android 17) tree and build, beside the 23.2 tree on the C: SSD.
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/build_lineage24.sh
#
# First run: `repo init` with --reference to the 23.2 tree (only Android 17's new
# objects download), the device fork's lineage-24.0 local manifest, `repo sync`,
# inline keys. Later runs: SYNC=1 to sync again (SYNC_JOBS, default 8, sets repo's
# parallel fetches); otherwise build only. BRANCHES="..." adds fork branches. Then the
# normal build_malachite.sh with TOP at this tree and MALACHITE_VER=24.0, which
# makes package_build.sh name the zip lineage-24.0-... and always a test build.
#
# Keys: setup_inline_keys.sh maps the APEXes of the 23.2 reference release only.
# APEXes new in Android 17 fall back to the AOSP test keys until they get keys of
# their own (make_keys.sh) and setup_inline_keys.sh runs with a 24.0 target-files.
set -o pipefail
TOOLS=/mnt/e/LineageOS-23.2-Malachite/tools
SRC=/mnt/wsl/malachite-build
T24=$SRC/lineage-24
LOG=$HOME/android/build-$(date +%Y%m%d-%H%M).log
phase() { echo "phase: $1 at $(date '+%F %T')" | tee -a "$LOG"; }
fail() { echo "build exit: 1 ($1)" | tee -a "$LOG"; exit 1; }

bash "$TOOLS/build_disk.sh" up || fail "build disk"
# build_disk.sh's keeper watches /build/.last-use and the 23.2 tree's heartbeat;
# keep it alive for this tree's whole sync and build.
( while sleep 60; do touch "$SRC/.last-use" 2>/dev/null; done ) &
HEARTBEAT=$!
trap 'kill $HEARTBEAT 2>/dev/null' EXIT

mkdir -p "$T24" && cd "$T24" || fail "no $T24"
phase "lineage-24.0 tree at $T24"
if [ ! -d .repo ]; then
  phase "repo init"
  repo init -q -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs \
    --no-clone-bundle --reference="$HOME/android/lineage" 2>&1 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "repo init failed"
  SYNC=1
fi
mkdir -p .repo/local_manifests
git -C "$HOME/android/lineage/device/xiaomi/malachite" fetch -q malachite-project lineage-24.0 &&
  git -C "$HOME/android/lineage/device/xiaomi/malachite" show \
    malachite-project/lineage-24.0:manifests/malachite.xml > .repo/local_manifests/malachite.xml ||
  fail "no lineage-24.0 local manifest"

if [ "${SYNC:-0}" = 1 ]; then
  phase "repo sync"
  git -C build/soong checkout -- ui/build/soong.go  # local memory patch, reapplied by build_malachite.sh
  # android.googlesource.com answers HTTP 429 (too many requests) when pushed hard;
  # SYNC_JOBS=4 eases off, --retry-fetches retries the refused fetches.
  repo sync -c -j"${SYNC_JOBS:-8}" --retry-fetches=3 --no-tags --no-clone-bundle --force-sync -q \
    2>&1 | tail -30 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "repo sync failed"
fi

if [ ! -f vendor/lineage-priv/keys/keys.mk ]; then
  phase "inline keys"
  TOP=$T24 bash "$TOOLS/setup_inline_keys.sh" 2>&1 | tail -5 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "setup_inline_keys.sh failed"
fi

# Tree state for the build log and next to the OTA. Every fork goes to the latest
# lineage-24.0 (since 2026-10-30 it holds all merged work), plus BRANCHES="a b"
# merged on top for testing (prepare_tree.sh, local merges only).
phase "prepare_tree.sh ${BRANCHES:-}"
# shellcheck disable=SC2086
TOP=$T24 BASE=lineage-24.0 bash "$TOOLS/prepare_tree.sh" ${BRANCHES:-} 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || fail "prepare_tree.sh failed"

phase "build_malachite.sh"
TOP=$T24 MALACHITE_VER=24.0 PREPARE=0 SYNC=0 bash "$TOOLS/build_malachite.sh"
