#!/system/bin/sh
#
# malachite: brightness fix for 20261016. system.prop does the work; it is applied before
# the display composer starts, which then never turns on sync backlight mode (led_type 1).

ui_print " "
ui_print "  malachite: brightness fix for 20261016"
ui_print " "

DEVICE=$(getprop ro.product.device)
ui_print "- Device: $DEVICE"
if [ "$DEVICE" != "malachite" ]; then
  abort "! This module targets malachite only. Aborting."
fi
ui_print "- Current led_type: $(cat /sys/class/leds/lcd-backlight/led_type 2>/dev/null)"

ui_print " "
ui_print "- Installed. Reboot to apply."
ui_print "- After the reboot led_type should read 0 and the slider should work."
ui_print "- To undo, remove the module and reboot."
ui_print " "
