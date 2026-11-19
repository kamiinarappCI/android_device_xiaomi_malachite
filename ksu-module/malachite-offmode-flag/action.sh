#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
v=$(flag)
echo "Flag now: $v"
if [ "$v" = 1 ]; then
  echo "ARMED: power off, then plug in -> charging screen expected."
else
  echo "Not armed yet. Wait 2 minutes after boot and press again."
fi
echo
echo "Last start:"
awk '/===== START/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$LOG" | tail -n 12
publish && echo && echo "Full log copied to Download/malachite_offmode.txt"
