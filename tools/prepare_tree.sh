#!/usr/bin/env bash
# Put the WSL build tree on lineage-23.2 (BASE=lineage-24.0 for the 24.0 tree)
# plus the feature branches to test.
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/prepare_tree.sh [branch ...]
#   bash .../prepare_tree.sh fix/lcd-density feature/fpsgo
#
# For every malachite-project fork in the local manifest: fetch lineage-23.2,
# check it out (detached HEAD), then merge each named branch that exists in
# that fork. A feature that touches several forks uses the same branch name in
# each, so one name brings in all of it. With no names the tree is plain
# lineage-23.2, which is what a release is built from. The merges stay local;
# nothing is pushed.
#
# Refuses (and changes nothing) when a fork has uncommitted changes, or when
# its HEAD has commits (other than this script's test merges) that are on no
# remote branch: commit that work to a branch and push it first.
# FORCE=1 skips both checks.
#
# Writes ~/android/tree-state.txt (copied into the build log and next to the
# OTA), so every test build records exactly what it contains.
set -uo pipefail
TOP=${TOP:-$HOME/android/lineage}
MANIFEST=${MANIFEST:-$TOP/.repo/local_manifests/malachite.xml}  # crdroid.xml for crDroid
STATE=$HOME/android/tree-state.txt
REMOTE=malachite-project
BASE=${BASE:-lineage-23.2}
if [ -d "$HOME/android/lineage-repo" ]; then  # moved to the SSD (migrate_build_disk.sh)
  bash "$(dirname "$0")/build_disk.sh" up >/dev/null || exit 1
fi
cd "$TOP" || exit 1

mapfile -t paths < <(python3 - "$MANIFEST" "$REMOTE" <<'PY'
import sys, xml.etree.ElementTree as ET
for p in ET.parse(sys.argv[1]).getroot().iter("project"):
    if p.get("remote") == sys.argv[2]:
        print(p.get("path"))
PY
)
[[ ${#paths[@]} -gt 0 ]] || { echo "no $REMOTE projects in $MANIFEST"; exit 1; }

# Heads an earlier run left, so they can be replaced without the safety check.
declare -A prepared=()
if [[ -f $STATE ]]; then
  while read -r path _ head _; do
    [[ $path == \#* || -z $path ]] && continue
    prepared[$path]=${head#head=}
  done < "$STATE"
fi

# Pass 1: check everything before touching anything.
fail=0
for p in "${paths[@]}"; do
  [[ -d $p/.git || -f $p/.git ]] || { echo "missing project $p (repo sync?)"; fail=1; continue; }
  [[ ${FORCE:-0} == 1 ]] && continue
  if [[ -n $(git -C "$p" status --porcelain --untracked-files=no) ]]; then
    echo "REFUSED $p: uncommitted changes"; git -C "$p" status --short --untracked-files=no | head -5 | sed 's/^/    /'
    fail=1; continue
  fi
  head=$(git -C "$p" rev-parse HEAD)
  # Merge commits are this script's own test merges (also those of a run that stopped on
  # a conflict); only real commits that exist nowhere else count.
  if [[ ${prepared[$p]:-} != "$head" ]] && [[ -n $(git -C "$p" log --oneline --no-merges HEAD --not --remotes | head -1) ]]; then
    echo "REFUSED $p: HEAD has commits that are on no remote branch:"
    git -C "$p" log --oneline --no-merges HEAD --not --remotes | head -5 | sed 's/^/    /'
    fail=1
  fi
done
[[ $fail == 0 ]] || { echo "nothing changed; commit and push the work above to a branch, or FORCE=1"; exit 1; }

# Pass 2: fetch, reset, merge.
tmp=$(mktemp)
{
  echo "# prepared $(date '+%F %T')"
  echo "# branches: $*"
} > "$tmp"
declare -A used=()
for p in "${paths[@]}"; do
  heads=$(git -C "$p" ls-remote --heads "$REMOTE" 2>/dev/null) || { echo "ls-remote failed: $p"; rm -f "$tmp"; exit 1; }
  want=("$BASE")
  for b in "$@"; do grep -q "refs/heads/$b\$" <<<"$heads" && want+=("$b"); done
  refspecs=(); for b in "${want[@]}"; do refspecs+=("+refs/heads/$b:refs/remotes/$REMOTE/$b"); done
  git -C "$p" fetch -q "$REMOTE" "${refspecs[@]}" || { echo "fetch failed: $p"; rm -f "$tmp"; exit 1; }
  git -C "$p" checkout -q --detach "$REMOTE/$BASE" || { echo "checkout failed: $p"; rm -f "$tmp"; exit 1; }
  base=$(git -C "$p" rev-parse --short HEAD)
  merged=()
  for b in "${want[@]:1}"; do
    if ! git -C "$p" -c user.name=Noam -c user.email=noamtu123@users.noreply.github.com \
         merge -q --no-ff --no-edit -m "test merge: $b" "$REMOTE/$b" >/dev/null 2>&1; then
      echo "CONFLICT in $p merging $b:"; git -C "$p" diff --name-only --diff-filter=U | sed 's/^/    /'
      git -C "$p" merge --abort
      echo "the tree is partly prepared; rebase $b on $BASE (or on the branch it conflicts with) and run again"
      rm -f "$tmp"; exit 1
    fi
    merged+=("$b@$(git -C "$p" rev-parse --short "$REMOTE/$b")")
    used[$b]=1
  done
  echo "$p base=$base head=$(git -C "$p" rev-parse HEAD) merged=$(IFS=,; echo "${merged[*]:-none}")" >> "$tmp"
done
mv "$tmp" "$STATE"
grep -v ' merged=none$' "$STATE"
unknown=0
for b in "$@"; do [[ -n ${used[$b]:-} ]] || { echo "ERROR: branch $b exists in no fork (typo, or not pushed?)"; unknown=1; }; done
[[ $unknown == 0 ]] || exit 1
echo "tree ready: $BASE${*:+ + $*}"
