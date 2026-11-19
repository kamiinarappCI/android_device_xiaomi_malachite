#!/system/bin/sh
ui_print " "
ui_print "  malachite off-mode charging fix (test)"
ui_print " "
DEVICE=$(getprop ro.product.device)
[ "$DEVICE" = malachite ] || abort "! malachite only (this phone: $DEVICE)"
for f in common.sh service.sh action.sh uninstall.sh; do set_perm "$MODPATH/$f" 0 0 0755; done
ui_print "- Reboot. 2 minutes after boot the Action button"
ui_print "  should say ARMED."
ui_print "- Then: power off, plug in -> charging screen."
ui_print "- Log: Download/malachite_offmode.txt (Action button)"
ui_print " "
