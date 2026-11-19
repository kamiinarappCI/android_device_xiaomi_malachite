#!/system/bin/sh
ui_print " "
ui_print "  malachite off-mode charging test"
ui_print " "
DEVICE=$(getprop ro.product.device)
ui_print "- Device: $DEVICE"
[ "$DEVICE" = malachite ] || abort "! This module targets malachite only. Aborting."

for f in common.sh post-fs-data.sh service.sh action.sh uninstall.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

ui_print "- Installed. Reboot, then test either way:"
ui_print "  A) Action button (cable plugged in)"
ui_print "  B) Power off, then plug in the cable"
ui_print "- Works if: charging screen shows and the phone"
ui_print "  stays off. Leave it 5 minutes, then hold power."
ui_print "- If it comes straight back into Android, test"
ui_print "  once more: the module then tries 'charger'."
ui_print "- Log: Download/malachite_offmode_test.txt"
ui_print "- It restarts at most once per test, never in a loop."
ui_print " "
