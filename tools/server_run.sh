#!/usr/bin/env bash
# Run one ROM build on the ServerHive rental from this PC, unattended:
# wait until the rental accepts ~/.ssh/serverhive_malachite, upload the scripts,
# start the build in tmux from a login shell, send the release keys when the build
# asks for them (server_send_keys.sh arms the key cleanup first), wait for the
# signed OTA and the key cleanup, then copy the results to E:\Android\Malachite\builds.
#
#   bash tools/server_run.sh malachite-24|evox|crdroid
#
# H=<user>@<host> and PORT (default 22) select the rental. PICKS="<path>:<fork branch> ..."
# cherry-picks one-commit fix branches on top (evox and crdroid only). SYNC=0 skips
# the repo sync of an existing server tree. One build at a time: two Soong analyses
# at once exceed the account's memory and both get killed (2026-11-10).
#
# Exits 0 when a signed OTA came home, 1 when the build or signing failed (logs are
# copied home either way), 2 when the rental never accepted the key.
set -uo pipefail
NAME=${1:?usage: server_run.sh malachite-24|evox|crdroid}
export H=${H:?set H=user@host} PORT=${PORT:-5156}
S=~/.ssh/serverhive_malachite
D=$(cd "$(dirname "$0")" && pwd)
case $NAME in
  malachite-24) SCRIPTS="server_build24.sh prepare_tree.sh server_sign24.sh"; RUN=server_build24.sh; OUT=lineage-24.0 ;;
  evox) SCRIPTS="server_build_evox.sh server_sign24.sh"; RUN=server_build_evox.sh; OUT=EvolutionX-cnb ;;
  crdroid) SCRIPTS="server_build_crdroid.sh server_sign24.sh"; RUN=server_build_crdroid.sh; OUT=crDroid-17.0 ;;
  *) echo "unknown build $NAME"; exit 1 ;;
esac
r() { ssh -i $S -o Port=$PORT -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=30 "$H" "$@"; }
log() { echo "[$(date '+%F %T')] $NAME: $*"; }

# 1. Wait for access (the user adds the key to each new rental themselves).
for i in $(seq 1 720); do r true 2>/dev/null && break; [ "$i" = 1 ] && log "waiting for the key on $H"; sleep 120; done
r true 2>/dev/null || { log "rental never accepted the key"; exit 2; }
log "connected: $(r 'hostname; nproc' | tr '\n' ' ')"

# 2. Upload and start, unless this build is already running or done.
if r "tmux has-session -t $NAME" 2>/dev/null; then
  log "already running, attaching to its log"
else
  r "mkdir -p ~/$NAME" && (cd "$D" && scp -i $S -o Port=$PORT -o BatchMode=yes $SCRIPTS "$H:$NAME/") || { log "upload failed"; exit 1; }
  r "tmux new-session -d -s $NAME 'PICKS=\"${PICKS:-}\" SYNC=${SYNC:-1} bash -l \$HOME/$NAME/$RUN'" || { log "tmux start failed"; exit 1; }
  log "build started"
fi

# 3. Keys when asked; then wait for the end of signing and key cleanup.
sent=0
while :; do
  sleep 60
  st=$(r "tail -c 4000 ~/$NAME/build.log 2>/dev/null" 2>/dev/null) || continue
  if [ $sent = 0 ] && grep -q "phase: waiting for the release keys" <<<"$st"; then
    bash "$D/server_send_keys.sh" "$NAME" && { sent=1; log "keys sent"; } || log "key send failed, retrying"
  fi
  grep -q "^keys deleted" <<<"$st" && break
  if grep -q "^build exit: [1-9]" <<<"$st" && [ $sent = 0 ]; then break; fi
done
log "$(grep -E '^build exit|^ota:|^keys deleted' <<<"$st" | tr '\n' ' ')"

# 4. Copy home.
dest=/e/Android/Malachite/builds/$OUT-$(date +%Y%m%d)-server
mkdir -p "$dest"
for f in build.log errors.txt tree-state.txt ota.log SHA256SUMS.txt sign.out keys-cleanup.log; do
  scp -q -i $S -o Port=$PORT -o BatchMode=yes "$H:$NAME/$f" "$dest/" 2>/dev/null
done
if grep -q "^ota: ok" <<<"$st"; then
  # Only the OTA and the three images flashed by fastboot come home; the target files
  # stay on the server (signing happens there).
  r "cd ~/$NAME && rm -rf images && unzip -q -o -j lineage_malachite-target_files.zip IMAGES/boot.img IMAGES/init_boot.img IMAGES/vendor_boot.img -d images && cd images && sha256sum *.img > ../images.sha256" ||
    { log "image extraction failed"; exit 1; }
  scp -q -i $S -o Port=$PORT -o BatchMode=yes "$H:$NAME/signed-ota_update.zip" "$H:$NAME/images/*.img" "$H:$NAME/images.sha256" "$dest/" &&
    (cd "$dest" && grep signed-ota_update.zip SHA256SUMS.txt | sha256sum -c && sha256sum -c images.sha256 &&
      sha256sum signed-ota_update.zip boot.img init_boot.img vendor_boot.img > SHA256SUMS.txt && rm images.sha256) &&
    { log "results in $dest"; exit 0; }
  log "copy or checksum failed ($dest)"; exit 1
fi
log "failed, logs in $dest"; exit 1
