#!/bin/bash
# Evolution X (Android 17, cnb) test build on a rented build server. Like
# server_build24.sh: builds target-files and otatools only; server_sign24.sh (with
# W=$HOME/evox) makes the signed OTA and deletes the keys afterwards.
#
#   scp server_build_evox.sh server_sign24.sh <server>:evox/
#   ssh -t <server> then: tmux new -d -s evox 'bash -l evox/server_build_evox.sh'
# Always from a login shell inside tmux: the server's scheduler kills builds started
# otherwise (setsid/nohup from a plain ssh command).
#
# The device tree comes from malachite-project evolutionx-24.0, whose
# manifests/evolution.xml pins every malachite project; nothing is merged locally
# unless PICKS names fix branches.
set -o pipefail
W=$HOME/evox
T=$W/src
LOG=$W/build.log
phase() { echo "phase: $1 at $(date '+%F %T')" | tee -a "$LOG"; }
fail() { echo "build exit: 1 ($1) at $(date '+%F %T')" | tee -a "$LOG"; exit 1; }
export GIT_AUTHOR_NAME=Noam GIT_AUTHOR_EMAIL=noamtu123@users.noreply.github.com
export GIT_COMMITTER_NAME=Noam GIT_COMMITTER_EMAIL=noamtu123@users.noreply.github.com

mkdir -p "$T" && cd "$T" || fail "no $T"
: > "$LOG"
phase "start (jobs ${JOBS:-server default})"
if [ ! -d .repo ]; then
  phase "repo init"
  repo init -q -u https://github.com/Evolution-X/manifest.git -b cnb --git-lfs --no-clone-bundle 2>&1 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "repo init failed"
  SYNC=1
fi
mkdir -p .repo/local_manifests
curl -fsSL https://raw.githubusercontent.com/malachite-project/android_device_xiaomi_malachite/evolutionx-24.0/manifests/evolution.xml \
  -o .repo/local_manifests/evolution.xml || fail "no evolution.xml"

if [ "${SYNC:-1}" = 1 ]; then
  phase "repo sync"
  repo sync -c -j"${SYNC_JOBS:-16}" --retry-fetches=5 --no-tags --no-clone-bundle --force-sync -q \
    2>&1 | tail -30 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" = 0 ] || fail "repo sync failed"
fi
# PICKS="<path>:<fork branch> ...": cherry-pick one-commit fix branches from the
# malachite-project forks (the sync is shallow, so --depth=2 brings the parent too).
for pk in ${PICKS:-}; do
  p=${pk%%:*}; b=${pk#*:}
  url=$(git -C "$p" remote get-url malachite-project 2>/dev/null) || fail "$p is not a malachite-project fork"
  git -C "$p" fetch -q --depth=2 "$url" "$b" || fail "fetch $b failed"
  subj=$(git -C "$p" log -1 --format=%s FETCH_HEAD)
  if git -C "$p" log -20 --format=%s | grep -qxF "$subj"; then
    echo "pick: $p $b already in" | tee -a "$LOG"
  else
    git -C "$p" cherry-pick FETCH_HEAD >/dev/null || fail "cherry-pick $b into $p failed"
    echo "pick: $p $b $(git -C "$p" rev-parse --short=12 HEAD)" | tee -a "$LOG"
  fi
done
{
  echo "# Evolution X cnb + malachite-project ($(date '+%F %T'))"
  for p in device/xiaomi/malachite vendor/xiaomi/malachite frameworks/base frameworks/native packages/apps/Settings \
           packages/services/Telephony packages/modules/Bluetooth hardware/mediatek hardware/xiaomi device/mediatek/sepolicy_vndr; do
    echo "$p $(git -C "$p" rev-parse --short=12 HEAD 2>/dev/null)"
  done
} > "$W/tree-state.txt"
cat "$W/tree-state.txt" >> "$LOG"

# Release keys are copied in from the PC (inline signing); never build with test keys.
if [ ! -f vendor/lineage-priv/keys/keys.mk ]; then
  phase "waiting for the release keys"
  for _ in $(seq 1 360); do [ -f vendor/lineage-priv/keys/keys.mk ] && break; sleep 10; done
  [ -f vendor/lineage-priv/keys/keys.mk ] || fail "no release keys after 60 min"
fi
unset WITH_ADB_INSECURE
# Keep the server's own build environment (login profile: RBE, CUSTOM_NINJA_BIN,
# ccache); its scheduler kills builds that override it or run outside a login shell.
source build/envsetup.sh >/dev/null
breakfast malachite userdebug >/dev/null || fail "breakfast failed"
# Evolution X's vendor config does not load lineage-priv itself; the device product
# inherits keys.mk. Stop rather than sign with the AOSP test keys if that fails.
cert=$(get_build_var PRODUCT_DEFAULT_DEV_CERTIFICATE)
echo "default certificate: $cert" | tee -a "$LOG"
[[ $cert == vendor/lineage-priv/keys/* ]] || fail "release keys not loaded"
phase compile
mka ${JOBS:+-j"$JOBS"} --skip-soong-tests target-files-package otatools 2>&1 | tee -a "$LOG" | grep -E "^FAILED|error:" | tail -40 > "$W/errors.txt"
status=${PIPESTATUS[0]}
TF=$(ls -t out/target/product/malachite/obj/PACKAGING/target_files_intermediates/*-target_files*.zip 2>/dev/null | head -1)
[ "$status" = 0 ] && [ -n "$TF" ] && cp "$TF" "$W/lineage_malachite-target_files.zip"
echo "build exit: $status at $(date '+%F %T')" | tee -a "$LOG"
exit "$status"
