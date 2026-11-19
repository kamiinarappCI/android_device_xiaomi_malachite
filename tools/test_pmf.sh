#!/bin/sh
# Exercise ksu-module/malachite-wpa3-fix/pmf.sh against scratch files.
set -u
SRC=$(cd "$(dirname "$0")/../ksu-module/malachite-wpa3-fix" && pwd)
W=$(mktemp -d); cp "$SRC/pmf.sh" "$W/"; export PMF_CONF="$W/wpa_supplicant.conf"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1  (want [$3] got [$2])"; fi; }
base() { printf 'update_config=1\nhs20=1\npmf=0\nsae_pwe=2\n' > "$PMF_CONF"; }

base; cp "$PMF_CONF" "$W/orig"; ino=$(stat -c %i "$PMF_CONF")
sh "$W/pmf.sh" apply
check "apply sets pmf=1"                "$(grep '^pmf=' "$PMF_CONF")" "pmf=1"
check "apply keeps the same inode"      "$(stat -c %i "$PMF_CONF")" "$ino"
check "apply leaves other lines alone"  "$(grep -vc '^pmf=' "$PMF_CONF")" "3"
check "apply leaves no temp file"       "$(ls -A "$W" | grep -c tmp)" "0"
sh "$W/pmf.sh" apply
check "apply is idempotent"             "$(grep -c '^pmf=' "$PMF_CONF")" "1"

echo "pmf=0" > "$W/orig_pmf"; sh "$W/pmf.sh" restore
check "restore gives back the original" "$(cmp -s "$PMF_CONF" "$W/orig" && echo same)" "same"
check "restore keeps the same inode"    "$(stat -c %i "$PMF_CONF")" "$ino"

printf 'update_config=1\nsae_pwe=2' > "$PMF_CONF"
sh "$W/pmf.sh" apply
check "apply adds pmf when absent"      "$(grep '^pmf=' "$PMF_CONF")" "pmf=1"
check "no-newline last line survives"   "$(grep -c '^sae_pwe=2$' "$PMF_CONF")" "1"
echo "none" > "$W/orig_pmf"; sh "$W/pmf.sh" restore
check "restore removes added pmf"       "$(grep -c '^pmf=' "$PMF_CONF")" "0"

rm -f "$PMF_CONF"; sh "$W/pmf.sh" apply
check "missing config is left alone"    "$([ -e "$PMF_CONF" ] && echo exists || echo absent)" "absent"

rm -rf "$W"; echo "pmf.sh: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
