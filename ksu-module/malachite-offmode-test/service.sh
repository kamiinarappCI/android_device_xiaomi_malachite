#!/system/bin/sh
# After boot: add what is only known later, and copy the log where the
# tester can find and share it.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 5
log "  sys.boot.reason=$(getprop sys.boot.reason) battery=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)%"
log "  history: $(getprop persist.sys.boot.reason.history | tr '\n' ' ')"
log "  next mode to test: $(mode)"

until [ -d /sdcard/Download ]; do sleep 2; done
cp "$LOG" /sdcard/Download/malachite_offmode_test.txt
