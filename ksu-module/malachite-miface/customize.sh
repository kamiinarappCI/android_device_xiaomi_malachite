#!/system/bin/sh
#
# malachite: Xiaomi face unlock (stock mifaced) instead of ParanoidSense
#
# The module form of feature/miface (device, vendor and Settings forks):
#
#   system/vendor  stock OS2.0.208.0 mifaced, its libraries and VINTF entry,
#                  plus four AOSP vendor libraries this ROM does not ship
#                  (face/common V3 NDK, vendor camera NDK, libdumpstateutil),
#                  built from the 23.2 tree
#   system.prop    ro.face.sense_service=false, so FaceService uses the HAL
#   sepolicy.rule  stock's hal_miface_default rules, on AOSP's hal_face_default
#   service.sh     starts and restarts mifaced (KernelSU cannot add init services)
#   REMOVE         ParanoidSense's app, overlays and permission files
#
# Not in the module: the Settings change from feature/miface. Settings opens
# the front camera for its enrollment preview while mifaced needs it too, so
# the preview may go black during enrollment; enrollment itself runs in the HAL.

ui_print " "
ui_print "  malachite: Xiaomi face unlock (stock mifaced)"
ui_print " "

DEVICE=$(getprop ro.product.device)
ui_print "- Device: $DEVICE"
[ "$DEVICE" = "malachite" ] || abort "! This module targets malachite only. Aborting."

VER=$(getprop ro.lineage.build.version)
ui_print "- LineageOS: $VER ($(getprop ro.lineage.display.version))"
[ "$VER" = "23.2" ] || abort "! Made for LineageOS 23.2 only. Aborting."

if [ -e /vendor/bin/hw/mifaced ] && [ ! -d /data/adb/modules/malachite_miface ]; then
  abort "! This ROM already ships mifaced. The module is not needed."
fi

# Stock 208 pieces the HAL loads from the ROM itself.
for f in /vendor/lib64/libteecli.so /vendor/lib64/libmisight.so /vendor/lib64/libmpbase.so \
         /vendor/mitee/ta /system/lib64/libmediandk.so; do
  [ -e "$f" ] || abort "! $f is missing on this ROM. Aborting."
done
ui_print "- Stock TEE and helper libraries: present"

if [ "$(dumpsys face 2>/dev/null | grep -ciE 'enrolled.*[1-9]|faces: [1-9]')" -gt 0 ]; then
  ui_print "!"
  ui_print "! A ParanoidSense face is still enrolled. It does not carry"
  ui_print "! over: delete it in Settings (or the framework drops it on"
  ui_print "! the first boot) and enroll again after the reboot."
  ui_print "!"
fi

V=$MODPATH/system/vendor
set_perm_recursive "$V" 0 0 0755 0644 u:object_r:vendor_file:s0
set_perm "$V/bin/hw/mifaced" 0 2000 0755 u:object_r:hal_face_default_exec:s0
set_perm "$V/etc/vintf/manifest/miface.xml" 0 0 0644 u:object_r:vendor_configs_file:s0
set_perm_recursive "$V/etc/vintf" 0 0 0755 0644 u:object_r:vendor_configs_file:s0

for f in post-fs-data.sh post-mount.sh service.sh action.sh uninstall.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

REMOVE="
/system/priv-app/ParanoidSense
/system/product/overlay/ParanoidSenseOverlay.apk
/system/product/overlay/ParanoidSense__lineage_malachite__auto_generated_rro_product.apk
/system/etc/permissions/privapp_whitelist_co.aospa.sense.xml
/system/etc/default-permissions/default_permissions_co.aospa.sense.xml
/system/etc/sysconfig/hiddenapi-whitelist-co.aospa.sense.xml
"
ui_print "- ParanoidSense: removed on the next boot"

ui_print " "
ui_print "- Installed. Reboot, then Settings > Security > Face unlock."
ui_print "- Status: Action button in the KernelSU app (also copies"
ui_print "  a log to Download/malachite_miface.txt)."
ui_print "- To undo, remove the module and reboot."
ui_print " "
