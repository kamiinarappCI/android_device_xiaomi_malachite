#!/system/bin/sh
# Action button: run the test now. Needs the cable plugged in.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

m=$(mode)
if [ "$m" = none ]; then
  echo "kpoc and charger both brought the phone straight back."
  echo "Log: Download/malachite_offmode_test.txt"
  echo "Starting over with kpoc; press again to retest."
  echo kpoc > "$STATE/mode"
  exit 0
fi

online=0
for f in /sys/class/power_supply/*/online; do
  [ "$(cat "$f" 2>/dev/null)" = 1 ] && online=1
done
if [ "$online" != 1 ]; then
  echo "Plug in the charger first, then press again."
  exit 0
fi

echo "Restarting into '$m' in 5 seconds."
echo "Expected if it works: the charging screen, and the phone stays off."
echo "Wait 5 minutes, then hold power to start it."
sleep 5
restart_into "$m"
