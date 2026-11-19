#!/system/bin/sh
# Early in every Android boot: record why the phone started, finish a
# pending test, and restart a cable-started boot into charging mode.
# This is the condition the ROM's init.mt6878.rc trigger uses.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

reason=$(getprop ro.boot.bootreason)
bootmode=$(getprop ro.bootmode)
log "BOOT: bootreason=$reason bootmode=$bootmode"

check_pending && exit 0

m=$(mode)
if [ "$reason" = usb ] && [ "$bootmode" = normal ]; then
  if [ "$m" = none ]; then
    log "Cable start detected; both modes already failed, not restarting."
  else
    log "Cable start detected (the case the ROM fix handles)."
    restart_into "$m"
  fi
fi
