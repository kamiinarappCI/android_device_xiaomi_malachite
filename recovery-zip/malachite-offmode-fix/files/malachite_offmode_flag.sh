#!/vendor/bin/sh
#
# Off-mode charging test fix (recovery zip, build 20261009).
#
# Writes power_off_mode = 1 straight to Xiaomi's charger partition, so the
# bootloader shows the charging screen when a cable starts the switched-off
# phone. Run by /product/etc/init/malachite_offmode_flag.rc when the charging
# screen starts and when Android powers off.
#
# Layout (kernel charger_partition.h): 4 KiB blocks; block 0 is the header
# (magic 0x20240725), block 1 is info_1 = u32 power_off_mode, zero_speed_mode,
# test, reserved. The 16 bytes written are what the kernel's own setter writes
# (mtk_battery.c charger_partition_poweroffmode_set): {1, 2, 0x34567890, 0}.
# The block device is used instead of the sysfs node because the node only
# works ~58 s after boot.

dev=/dev/block/by-name/charger
log() { echo "malachite_offmode: $*" > /dev/kmsg; }

magic=$(/vendor/bin/od -A n -t x4 -N 4 "$dev" | /vendor/bin/tr -d ' ')
if [ "$magic" != 20240725 ]; then
  log "charger partition header not found (read '$magic'), nothing written"
  exit 1
fi

/vendor/bin/printf '\001\000\000\000\002\000\000\000\220\170\126\064\000\000\000\000' |
  /vendor/bin/dd of="$dev" bs=16 seek=256 count=1 conv=notrunc,fsync 2>/dev/null

value=$(/vendor/bin/od -A n -t x4 -j 4096 -N 4 "$dev" | /vendor/bin/tr -d ' ')
if [ "$value" = 00000001 ]; then
  log "power_off_mode set to 1 ($1)"
  exit 0
fi
log "power_off_mode write failed (reads '$value') ($1)"
exit 1
