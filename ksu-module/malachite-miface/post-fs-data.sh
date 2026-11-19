#!/system/bin/sh
# Runs before KernelSU mounts this module's system/ files.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

# A ROM with mifaced built in (feature/miface) needs none of this; two
# copies would fight over the HAL's service names.
if [ -e "$HAL" ]; then
  touch "$MODDIR/skip_mount" "$MODDIR/disable"
  log "ROM ships $HAL itself: module disabled, remove it"
  exit 0
fi

# Stock's miface.rc: mkdir /data/vendor/face 775 system system
mkdir -p "$FACE_DATA"
chown 1000:1000 "$FACE_DATA"
chmod 0775 "$FACE_DATA"
chcon -R u:object_r:face_vendor_data_file:s0 "$FACE_DATA"
