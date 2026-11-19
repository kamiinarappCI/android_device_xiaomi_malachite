#!/system/bin/sh
#
# malachite WPA3 (SAE) association fix
#
# The malachite Wi-Fi driver (wlan_drv_gen4m_6878.ko) decodes only the nl80211
# WPA version bits 0x1 and 0x2. Android 16's supplicant sends
# NL80211_WPA_VERSION_3 (0x4) for SAE, which the driver maps to
# IW_AUTH_WPA_VERSION_DISABLED; the AKM is discarded and association ends in
# CTRL-EVENT-ASSOC-REJECT status_code=16. WPA3 also needs protected management
# frames (pmf=1), or the access point refuses with status 31.
#
# Nothing is tied to one ROM build. At install and on every boot, wpa3.sh
# checks this ROM's own wpa_supplicant and configuration and fixes only what
# is wrong:
#   - version bit: finds the SAE "ver |= 4" in nl80211_connect_common() and
#     changes it to 2 in a copy that KernelSU mounts over /vendor. A ROM that
#     already has the fix is left alone.
#   - pmf: sets pmf=1 in the live configuration and the vendor template if
#     they do not have it.
# /vendor itself is never modified.

ui_print " "
ui_print "  malachite WPA3 (SAE) association fix"
ui_print " "

DEVICE=$(getprop ro.product.device)
ui_print "- Device: $DEVICE"
if [ "$DEVICE" != "malachite" ]; then
  abort "! This module targets malachite only. Aborting."
fi

for f in wpa3.sh pmf.sh post-fs-data.sh uninstall.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

ui_print "- Checking this ROM's wpa_supplicant (takes a few seconds)"
sh "$MODPATH/wpa3.sh" refresh "$MODPATH" | while read -r line; do ui_print "- $line"; done
[ -f "$MODPATH/system/vendor/etc/wifi/wpa_supplicant.conf" ] &&
  ui_print "- Vendor template lacks pmf=1: overlay added"

# Remember the live pmf value to restore on uninstall. Carry it over from a
# previous install, so an upgrade never records our own pmf=1 as the original.
DATA_CONF=/data/vendor/wifi/wpa/wpa_supplicant.conf
PREV_ORIG=/data/adb/modules/malachite_wpa3_fix/orig_pmf
if [ -f "$PREV_ORIG" ]; then
  cp "$PREV_ORIG" "$MODPATH/orig_pmf"
elif [ -f "$DATA_CONF" ]; then
  ORIG_LINE=$(grep -m1 '^pmf=' "$DATA_CONF")
  echo "${ORIG_LINE:-none}" > "$MODPATH/orig_pmf"
else
  echo "none" > "$MODPATH/orig_pmf"
fi
ui_print "- Live pmf before this module: $(cat "$MODPATH/orig_pmf"); set to pmf=1 on every boot"

ui_print " "
ui_print "- Installed. Reboot to apply."
ui_print "- The KernelSU app shows what the module did in its description."
ui_print "- After a ROM update it re-checks by itself; no reinstall needed."
ui_print "- To undo everything, REMOVE the module (not just disable it)"
ui_print "  so pmf is restored. Nothing on /vendor was modified."
ui_print " "
