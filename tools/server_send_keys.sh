#!/usr/bin/env bash
# Send the release keys (vendor/lineage-priv of the crDroid tree on this PC) to a
# server build that waits for them, after arming server_sign24.sh, which deletes
# them (and every copy the build makes) as soon as the build ends.
#
#   bash tools/server_send_keys.sh malachite-24  # tree ~/malachite-24/lineage-24
#   bash tools/server_send_keys.sh evox          # tree ~/evox/src
#   bash tools/server_send_keys.sh crdroid       # tree ~/crdroid/src
#
# Run from Git Bash on this PC. Uses the ServerHive key ~/.ssh/serverhive_malachite;
# H=<user>@<host> selects the rental (each rental is a new account).
set -euo pipefail
NAME=${1:?usage: server_send_keys.sh <folder under the server home>}
S=~/.ssh/serverhive_malachite
H=${H:?set H=user@host} PORT=${PORT:-5156}
case $NAME in
  evox|crdroid) TREE=src ;;
  malachite-24) TREE=lineage-24 ;;
  *) echo "unknown folder $NAME"; exit 1 ;;
esac

ssh -i $S -o Port=$PORT -o BatchMode=yes "$H" "test -d ~/$NAME/$TREE/vendor && test ! -e ~/$NAME/$TREE/vendor/lineage-priv && ! grep -q '^build exit' ~/$NAME/build.log" ||
  { echo "server not waiting (no tree, keys already there, or the build already ended)"; exit 1; }
# Arm the cleanup first, so the keys can never outlive the build. It runs the OTA
# signing too, so it starts like a build: in tmux, from a login shell.
ssh -i $S -o Port=$PORT -o BatchMode=yes "$H" \
  "tmux new-session -d -s $NAME-sign 'W=\$HOME/$NAME T=\$HOME/$NAME/$TREE bash -l \$HOME/$NAME/server_sign24.sh > \$HOME/$NAME/sign.out 2>&1'" || true
ssh -i $S -o Port=$PORT -o BatchMode=yes "$H" 'pgrep -f server_sign24.sh >/dev/null' || { echo "cleanup job did not start"; exit 1; }
MSYS_NO_PATHCONV=1 wsl.exe tar -C /mnt/wsl/malachite-build/crdroid-17.0/vendor -czf - lineage-priv |
  ssh -i $S -o Port=$PORT -o BatchMode=yes "$H" "umask 077; tar -xzf - -C ~/$NAME/$TREE/vendor && chmod -R go-rwx ~/$NAME/$TREE/vendor/lineage-priv && echo keys: \$(ls ~/$NAME/$TREE/vendor/lineage-priv/keys | wc -l)"
