#!/system/bin/sh
# Every Android start: record what the bootloader saw, then set the flag to 1
# once the charger memory accepts writes (the kernel resets it ~1 min after
# boot), and keep it at 1. The bootloader uses a 1 only when a cable starts a
# switched-off phone; it resets the flag to 2 at every start, so this cannot loop.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# Keep the log small: last 2000 lines.
[ -f "$LOG" ] && tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

log "===== START"
reason=$(sed -n 's/^androidboot\.bootreason = "\(.*\)"/\1/p' /proc/bootconfig | tr 'A-Z' 'a-z')
case "$reason" in
  usb*|*charger*) log "RESULT: FAIL - the cable started Android (bootreason=$reason)" ;;
  *) log "RESULT: OK - started by: ${reason:-unknown} (not the cable)" ;;
esac
log "bootconfig: $(grep -E 'androidboot\.(bootreason|bootmode)' /proc/bootconfig | tr '\n' ' ')"
log "bootloader saw: $(grep -a -E 'XMCHG' /proc/pl_lk 2>/dev/null | grep -a -i -E 'power_off_mode|poweroffmode' | tr '\n' ' ')"
for f in /sys/fs/pstore/console-ramoops*; do
  [ -f "$f" ] || continue
  log "previous shutdown: $(grep -a -i -E 'poweroffmode|charger_partition' "$f" | tail -5 | tr '\n' ' ')"
done
log "flag at start: $(flag)"
log "charger unplug delay: $(getprop ro.product.charger.unplugged_shutdown_time) ms (empty = default 10000; recovery zip sets 90000)"

# Watch the flag until the kernel has reset it and writes stick.
last=
i=0
while [ $i -lt 150 ]; do      # up to ~5 minutes
  v=$(flag)
  [ "$v" != "$last" ] && log "flag reads $v" && last=$v
  if [ "$v" = 1 ] || [ "$v" = 2 ]; then
    sleep 2
    echo 1 > "$NODE" 2>/dev/null
    sleep 5
    v=$(flag)
    if [ "$v" = 1 ]; then log "ARMED: flag set to 1"; break; fi
    log "write did not stick (reads $v), retrying"
  fi
  sleep 2
  i=$((i + 1))
done
[ "$(flag)" = 1 ] || log "FAILED to arm within 5 minutes (flag $(flag))"
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
publish

# Keep it at 1: check every minute, log and fix anything that resets it.
while true; do
  sleep 60
  v=$(flag)
  if [ "$v" != 1 ]; then
    log "flag was reset to $v while running; setting 1 again"
    echo 1 > "$NODE" 2>/dev/null
    log "flag now $(flag)"
    publish
  fi
done
