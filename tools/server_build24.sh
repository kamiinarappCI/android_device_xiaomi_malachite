#!/bin/bash
# LineageOS 24.0 test build on a rented build server (ServerHive). Builds
# target-files and otatools with the release keys (inline signing); server_sign24.sh
# makes the signed OTA and deletes the keys afterwards (server_send_keys.sh sends them).
#
#   scp server_build24.sh prepare_tree.sh server_sign24.sh <server>:malachite-24/
#   ssh -t <server> then: tmux new -d -s malachite-24 'BRANCHES="..." bash -l malachite-24/server_build24.sh'
# Always from a login shell inside tmux: the server's scheduler kills builds started
# otherwise (setsid/nohup from a plain ssh command) or with its environment overridden.
#
# Everything lives in ~/malachite-24 (rentals can be shared with other users; their
# trees and global git config are left alone). SYNC=0 skips repo sync on a rerun.
set -o pipefail
W=$HOME/malachite-24
T=$W/lineage-24
LOG=$W/build.log
phase() { echo "phase: $1 at $(date '+%F %T')" | tee -a "$LOG"; }
fail() { echo "build exit: 1 ($1) at $(date '+%F %T')" | tee -a "$LOG"; exit 1; }
export GIT_AUTHOR_NAME=Noam GIT_AUTHOR_EMAIL=noamtu123@users.noreply.github.com
export GIT_COMMITTER_NAME=Noam GIT_COMMITTER_EMAIL=noamtu123@users.noreply.github.com

mkdir -p "$T" && cd "$T" || fail "no $T"
: > "$LOG"
phase "start (jobs ${JOBS:-server default}) branches: ${BRANCHES:-none}"
if [ ! -d .repo ]; then
  phase "repo init"
  repo init -q -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs \
    --no-clone-bundle 2>&1 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "repo init failed"
  SYNC=1
fi
mkdir -p .repo/local_manifests
curl -fsSL https://raw.githubusercontent.com/malachite-project/android_device_xiaomi_malachite/lineage-24.0/manifests/malachite.xml \
  -o .repo/local_manifests/malachite.xml || fail "no lineage-24.0 local manifest"

if [ "${SYNC:-1}" = 1 ]; then
  phase "repo sync"
  repo sync -c -j"${SYNC_JOBS:-16}" --retry-fetches=5 --no-tags --no-clone-bundle --force-sync -q \
    2>&1 | tail -30 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "repo sync failed"
fi

# repo sync clones shallowly here, and a merge into a one-commit history fails with
# "refusing to merge unrelated histories". Test branches are a few commits away from
# lineage-24.0, so some history is enough (frameworks/base is too big to unshallow).
# Without BRANCHES nothing is merged, so the history is not needed (frameworks/base
# alone takes 15 minutes or more).
if [ -n "${BRANCHES:-}" ]; then
phase "deepen the malachite-project forks"
python3 - .repo/local_manifests/malachite.xml <<'PY' > "$W/forks.txt"
import sys, xml.etree.ElementTree as ET
for p in ET.parse(sys.argv[1]).getroot().iter("project"):
    if p.get("remote") == "malachite-project":
        print(p.get("path"))
PY
while read -r p; do
  [ "$(git -C "$p" rev-parse --is-shallow-repository 2>/dev/null)" = true ] || continue
  # Still shallow after a deepen, so count what is there instead of deepening again.
  [ "$(git -C "$p" rev-list --count HEAD)" -lt 100 ] || continue
  git -C "$p" fetch -q --deepen=500 malachite-project lineage-24.0 || fail "deepen $p failed"
done < "$W/forks.txt"
fi

phase "prepare_tree.sh ${BRANCHES:-}"
# prepare_tree.sh writes ~/android/tree-state.txt; keep it in this folder instead.
sed "s#^STATE=.*#STATE=$W/tree-state.txt#" "$W/prepare_tree.sh" > "$W/.prepare_tree.sh"
# shellcheck disable=SC2086
TOP=$T BASE=lineage-24.0 bash "$W/.prepare_tree.sh" ${BRANCHES:-} 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || fail "prepare_tree.sh failed"

# Release keys are copied in from the PC (inline signing); never build with test keys.
if [ ! -f vendor/lineage-priv/keys/keys.mk ]; then
  phase "waiting for the release keys"
  for _ in $(seq 1 360); do [ -f vendor/lineage-priv/keys/keys.mk ] && break; sleep 10; done
  [ -f vendor/lineage-priv/keys/keys.mk ] || fail "no release keys after 60 min"
fi
# Release type, as build_malachite.sh does without DIAGNOSTIC=1.
unset WITH_ADB_INSECURE
export MALACHITE_RELEASE=true MALACHITE_VER=24.0
# Keep the server's own build environment (login profile: RBE, CUSTOM_NINJA_BIN,
# ccache); its scheduler kills builds that override it or run outside a login shell.
source build/envsetup.sh >/dev/null
breakfast malachite userdebug >/dev/null || fail "breakfast failed"
cert=$(get_build_var PRODUCT_DEFAULT_DEV_CERTIFICATE)
echo "default certificate: $cert" | tee -a "$LOG"
[[ $cert == vendor/lineage-priv/keys/* ]] || fail "release keys not loaded"
phase compile
mka ${JOBS:+-j"$JOBS"} --skip-soong-tests target-files-package otatools 2>&1 | tee -a "$LOG" | grep -E "^FAILED|error:|^\[100%" | tail -40 > "$W/errors.txt"
status=${PIPESTATUS[0]}
TF=$(ls -t out/target/product/malachite/obj/PACKAGING/target_files_intermediates/*-target_files*.zip 2>/dev/null | head -1)
[ "$status" = 0 ] && [ -n "$TF" ] && { cp "$TF" "$W/lineage_malachite-target_files.zip"; sha256sum "$W/lineage_malachite-target_files.zip" > "$W/target_files.sha256"; }
echo "build exit: $status at $(date '+%F %T')" | tee -a "$LOG"
exit "$status"
