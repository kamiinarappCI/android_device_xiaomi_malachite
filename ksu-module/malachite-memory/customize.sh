#!/system/bin/sh
#
# malachite memory: keep more apps in the background
#
# Only system.prop does the work; this script checks the device and records
# the value the ROM ships, so the change can be compared later.

ui_print " "
ui_print "  malachite memory: keep more apps in the background"
ui_print " "

DEVICE=$(getprop ro.product.device)
ui_print "- Device: $DEVICE"
if [ "$DEVICE" != "malachite" ]; then
  abort "! This module targets malachite only. Aborting."
fi

ui_print "- ROM value: ro.lmk.swap_free_low_percentage=$(getprop ro.lmk.swap_free_low_percentage)"
ui_print "- Module value: 20 (stock Xiaomi)"

for f in service.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

ui_print " "
ui_print "- Installed. Reboot to apply."
ui_print "- To undo, remove the module and reboot."
ui_print " "
