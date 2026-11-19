#!/usr/bin/env bash
# Attach the build tree on the C: SSD to Ubuntu at ~/android/lineage.
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/build_disk.sh up       # before using the tree
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/build_disk.sh status
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/build_disk.sh down     # release it now
#
# The source checkout and out/ live in the tiny WSL distribution MalachiteBuild,
# whose disk is C:\WSL\MalachiteBuild\ext4.vhdx (make_build_disk_rootfs.sh).
# When it starts it bind-mounts its /build at /mnt/wsl/malachite-build, which all
# WSL 2 distributions share; `up` mounts /mnt/wsl/malachite-build/lineage over
# ~/android/lineage, so every path stays as before. The git history stays on the
# E: disk: ~/android/lineage/.repo is a link to ~/android/lineage-repo.
#
# WSL stops an idle distribution within about a minute, which would pull the tree
# away from under a build, so `up` starts a keeper inside MalachiteBuild. The
# keeper exits on its own IDLE_HOURS (3, like the VM's idle timeout in
# .wslconfig) after the newest heartbeat: `up` touches /build/.last-use, and
# build_malachite.sh touches lineage/.build-heartbeat every minute while it runs.
# After that MalachiteBuild and the VM can stop and free their memory; the next
# `up` starts them again. Every tool that uses the tree (build_malachite.sh,
# prepare_tree.sh) runs `up` first.
set -uo pipefail
TREE=$HOME/android/lineage
SRC=/mnt/wsl/malachite-build
STATE=$HOME/android/.build-disk
IDLE_SECONDS=$(( ${IDLE_HOURS:-3} * 3600 ))
WSL=/mnt/c/Windows/System32/wsl.exe
mkdir -p "$STATE"

mounted() { findmnt -n -M "$TREE" -o SOURCE 2>/dev/null | grep -q '\[/build/lineage\]'; }
alive() { ls "$TREE/build/envsetup.sh" >/dev/null 2>&1; }
src_up() { findmnt -n "$SRC" >/dev/null 2>&1 && ls "$SRC" >/dev/null 2>&1; }
asroot() { "$WSL" -d Ubuntu -u root -e "$@"; }

# Runs inside MalachiteBuild (only its own tiny userland is there).
KEEPER='while :; do
  now=$(/bin/date +%s)
  last=$(/bin/stat -c %Y /build/.last-use /build/lineage/.build-heartbeat 2>/dev/null | /bin/sort -n | /bin/tail -1)
  [ $((now - ${last:-0})) -lt '"$IDLE_SECONDS"' ] || exit 0
  /bin/sleep 120
done'

keeper_running() { [ -f "$STATE/keeper.pid" ] && kill -0 "$(cat "$STATE/keeper.pid")" 2>/dev/null; }

case "${1:-status}" in
  up)
    if ! keeper_running; then
      # The keeper must see a fresh heartbeat before its first check.
      "$WSL" -d MalachiteBuild -u root -e /bin/touch /build/.last-use || { echo "cannot start MalachiteBuild"; exit 1; }
      setsid nohup "$WSL" -d MalachiteBuild -u root -e /bin/sh -c "$KEEPER" >/dev/null 2>&1 &
      echo $! > "$STATE/keeper.pid"
    fi
    for _ in $(seq 60); do src_up && break; sleep 1; done
    if ! src_up && findmnt -n "$SRC" >/dev/null 2>&1; then
      # A stale mount from an instance that stopped: restart MalachiteBuild,
      # whose boot command replaces it.
      "$WSL" --terminate MalachiteBuild >/dev/null 2>&1
      "$WSL" -d MalachiteBuild -u root -e /bin/touch /build/.last-use
      [ -f "$STATE/keeper.pid" ] && kill "$(cat "$STATE/keeper.pid")" 2>/dev/null
      setsid nohup "$WSL" -d MalachiteBuild -u root -e /bin/sh -c "$KEEPER" >/dev/null 2>&1 &
      echo $! > "$STATE/keeper.pid"
      for _ in $(seq 60); do src_up && break; sleep 1; done
    fi
    src_up || { echo "MalachiteBuild did not start (no $SRC)"; exit 1; }
    # The keeper's first touch runs as root; hand the file to this user.
    [ -O "$SRC/.last-use" ] || asroot chown "$(id -u):$(id -g)" "$SRC/.last-use"
    touch "$SRC/.last-use"
    if mounted && ! alive; then asroot umount -l "$TREE"; fi   # stale after a stop
    # The 23.2 tree is gone since 2026-11-10; trees that live directly on the disk
    # (crdroid-17.0) only need $SRC itself.
    if [ -d "$SRC/lineage" ] && ! mounted; then
      mkdir -p "$TREE"
      asroot mount --bind "$SRC/lineage" "$TREE" || { echo "mount failed"; exit 1; }
      alive || { echo "build tree not readable at $TREE"; exit 1; }
    fi
    echo "build disk up: $(df -h "$SRC" | awk 'NR==2 {print $3 " used, " $4 " free"}')"
    ;;
  down)
    if pgrep -f "build_malachite.sh|prepare_tree.sh|soong_ui|ninja|repo sync" >/dev/null; then
      echo "the build tree is in use; not releasing it"; exit 1
    fi
    mounted && asroot umount "$TREE"
    keeper_running && kill "$(cat "$STATE/keeper.pid")"
    rm -f "$STATE/keeper.pid"
    echo "build disk released"
    ;;
  status)
    echo "keeper: $(keeper_running && echo running || echo stopped)"
    echo "MalachiteBuild: $(src_up && echo up || echo down)"
    echo "mounted: $(mounted && echo yes || echo no), readable: $(alive && echo yes || echo no)"
    mounted && df -h "$TREE" | tail -1
    ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
