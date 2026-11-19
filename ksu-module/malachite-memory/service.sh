#!/system/bin/sh
# system.prop is applied before lmkd starts, so this is a fallback: if lmkd
# came up with a different value, ask it to re-read its properties.
MODDIR=${0%/*}
LOG=/data/local/tmp/malachite_memory.log
WANT=20

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done

HAVE=$(getprop ro.lmk.swap_free_low_percentage)
if [ "$HAVE" != "$WANT" ]; then
  echo "$(date): property is $HAVE, expected $WANT" >> "$LOG" 2>/dev/null
  exit 0
fi
setprop lmkd.reinit 1
echo "$(date): ro.lmk.swap_free_low_percentage=$HAVE, lmkd re-read its settings" >> "$LOG" 2>/dev/null
