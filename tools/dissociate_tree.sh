#!/bin/bash
# Make a repo checkout stop borrowing objects from another tree (repo init --reference),
# so that tree can be deleted.
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/dissociate_tree.sh <tree>
#
# repo's own --dissociate runs `git repack -a -d`, which git refuses in the shared object
# stores repo marks preciousObjects. So, for every git dir under .repo whose object store
# has info/alternates: `git repack -a` from that git dir's refs (no -d, so nothing is
# deleted; no -l, so the borrowed objects are copied in). Then each alternates file
# becomes alternates.dissociated, and every such git dir must pass
# `git fsck --connectivity-only`. A git dir that fails gets its alternates back and the
# script exits 1. JOBS (default 4) git dirs at a time.
set -uo pipefail
T=${1:?tree}
cd "$T/.repo" || exit 1
JOBS=${JOBS:-4}

mapfile -t alts < <(find . -path '*/objects/info/alternates' 2>/dev/null)
[ ${#alts[@]} = 0 ] && { echo "nothing borrowed"; exit 0; }
declare -A borrow=()
for a in "${alts[@]}"; do borrow[$(readlink -f "${a%/info/alternates}")]=1; done

list=$(mktemp)
while IFS= read -r g; do
  od=$(readlink -f "$g/objects" 2>/dev/null) || continue
  [ -n "${borrow[$od]:-}" ] && echo "$PWD/$g" >> "$list"
done < <(find projects project-objects manifests.git -type d -name '*.git' -prune 2>/dev/null)
echo "$(date '+%T') ${#alts[@]} object stores borrow; repacking $(wc -l < "$list") git dirs"

fails=$(mktemp)
xargs -a "$list" -P "$JOBS" -I{} sh -c 'git --git-dir="$1" repack -a -q || echo "repack $1" >> "$2"' _ {} "$fails"
[ -s "$fails" ] && { echo "repack failed:"; cat "$fails"; exit 1; }
echo "$(date '+%T') repacked"

for a in "${alts[@]}"; do mv "$a" "$a.dissociated"; done
xargs -a "$list" -P "$JOBS" -I{} sh -c \
  'git --git-dir="$1" fsck --connectivity-only --no-dangling --no-progress >/dev/null 2>&1 || echo "$1" >> "$2"' _ {} "$fails"
if [ -s "$fails" ]; then
  echo "$(date '+%T') fsck failed in $(wc -l < "$fails") git dirs; their alternates are restored:"
  while IFS= read -r g; do
    od=$(readlink -f "$g/objects")
    [ -f "$od/info/alternates.dissociated" ] && mv "$od/info/alternates.dissociated" "$od/info/alternates"
    echo "  $g"
  done < "$fails"
  exit 1
fi
echo "$(date '+%T') dissociated: every git dir passes fsck --connectivity-only without alternates"
