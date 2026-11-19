#!/system/bin/sh
# Module removed: ParanoidSense comes back with the ROM's files on the next
# boot. Turn its overlays back on and delete the faces mifaced stored.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

for o in $SENSE_OVERLAYS; do
  cmd overlay enable "$o" >/dev/null 2>&1
done
rm -rf "$FACE_DATA"
rm -f "$LOG"
