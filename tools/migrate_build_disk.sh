#!/usr/bin/env bash
# One-time move of the build tree's source checkout, out/ and ccache to the C:
# SSD (MalachiteBuild distribution, see build_disk.sh). The git history (.repo)
# stays on the E: disk as ~/android/lineage-repo.
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/migrate_build_disk.sh copy     # copy (re-runnable)
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/migrate_build_disk.sh switch   # use the copy
#
# `copy` never changes the E: tree. `switch` refuses while anything builds or
# syncs, makes a last copy pass, then: .repo -> ~/android/lineage-repo, the old
# tree -> ~/android/lineage-hdd-old (kept until a build from the SSD works; then
# it goes to ~/_to-delete), and ~/android/lineage becomes the SSD tree.
# Log: ~/android/migrate-build-disk.log
set -uo pipefail
OLD=$HOME/android/lineage
SRC=/mnt/wsl/malachite-build
NEW=$SRC/lineage
REPO=$HOME/android/lineage-repo
LOG=$HOME/android/migrate-build-disk.log
TOOLS=/mnt/e/LineageOS-23.2-Malachite/tools
WSL=/mnt/c/Windows/System32/wsl.exe

say() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

keep_alive() {  # keeper + heartbeat while this script runs
  "$WSL" -d MalachiteBuild -u root -e /bin/touch /build/.last-use || exit 1
  setsid nohup "$WSL" -d MalachiteBuild -u root -e /bin/sleep infinity >/dev/null 2>&1 &
  KEEP=$!
  for _ in $(seq 60); do ls "$SRC" >/dev/null 2>&1 && break; sleep 1; done
  ls "$SRC" >/dev/null 2>&1 || { say "MalachiteBuild did not start"; exit 1; }
  trap 'kill $KEEP 2>/dev/null' EXIT
}

copy_pass() {
  mkdir -p "$NEW" "$SRC/ccache"
  # Leftovers of earlier builds that every build writes again.
  rsync -aH --delete --info=stats1 \
    --exclude=/.repo \
    --exclude=/signed-target_files.zip --exclude=/signed-ota_update.zip \
    --exclude='/out/target/product/malachite/obj/PACKAGING/target_files_intermediates/' \
    --exclude='/out/target/product/malachite/lineage_malachite-ota*.zip' \
    --exclude='/out/target/product/malachite/lineage-*.zip' \
    "$OLD/" "$NEW/" 2>&1 | tail -12 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  rsync -a --delete --info=stats1 "$HOME/.cache/ccache/" "$SRC/ccache/" 2>&1 | tail -3 | tee -a "$LOG"
  return "$rc"
}

case "${1:-}" in
  copy)
    keep_alive
    say "copy: start ($(du -sh --exclude=.repo "$OLD" 2>/dev/null | cut -f1) to copy)"
    copy_pass; rc=$?
    say "copy: rsync exit $rc; SSD now $(df -h "$SRC" | awk 'NR==2 {print $3 " used, " $4 " free"}')"
    echo "MIGRATE-COPY-DONE rc=$rc" | tee -a "$LOG"
    ;;
  switch)
    [ -d "$OLD/.repo" ] || { say "switch: $OLD/.repo missing (already switched?)"; exit 1; }
    if pgrep -f "build_malachite.sh|prepare_tree.sh|soong_ui|ninja|repo sync" >/dev/null; then
      say "switch: the tree is in use"; exit 1
    fi
    keep_alive
    say "switch: last copy pass"
    copy_pass || { say "switch: copy failed, nothing switched"; exit 1; }
    # Compare file counts outside .repo before switching.
    a=$(cd "$OLD" && find . -path ./.repo -prune -o -path ./out/target/product/malachite/obj/PACKAGING/target_files_intermediates -prune -o -print 2>/dev/null | grep -vcE '^\./(signed-|out/target/product/malachite/(lineage-|lineage_malachite-ota))')
    b=$(cd "$NEW" && find . -print 2>/dev/null | wc -l)
    say "switch: entries old=$a new=$b"
    [ "$a" -le "$b" ] && [ $((b - a)) -lt 100 ] || { say "switch: counts differ, nothing switched"; exit 1; }
    mv "$OLD/.repo" "$REPO" || exit 1
    ln -sfn "$REPO" "$NEW/.repo"
    mv "$OLD" "$HOME/android/lineage-hdd-old" || { mv "$REPO" "$OLD/.repo"; rm -f "$NEW/.repo"; exit 1; }
    mkdir -p "$OLD"
    bash "$TOOLS/build_disk.sh" up | tee -a "$LOG" || exit 1
    git -C "$OLD/frameworks/base" rev-parse --short HEAD >/dev/null && git -C "$OLD/device/xiaomi/malachite" status --short | head -3
    say "switch: done; ~/android/lineage is on the SSD, .repo on E: ($REPO), old tree in ~/android/lineage-hdd-old"
    echo "MIGRATE-SWITCH-DONE" | tee -a "$LOG"
    ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
