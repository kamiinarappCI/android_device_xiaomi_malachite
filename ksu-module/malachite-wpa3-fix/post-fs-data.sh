#!/system/bin/sh
# Runs early in boot, before the framework starts the supplicant and before
# KernelSU mounts this module's system/ files, so the ROM's own
# /vendor/bin/hw/wpa_supplicant is normally what this sees. wpa3.sh re-checks
# it only when it changed (a ROM update) and rebuilds or drops the patched copy.
MODDIR=${0%/*}
LOG=${WPA3_FIX_LOG:-/data/local/tmp/malachite_wpa3_fix.log}

out=$(sh "$MODDIR/wpa3.sh" refresh "$MODDIR")
[ -n "$out" ] && echo "$(date): $out" >> "$LOG" 2>/dev/null
sh "$MODDIR/pmf.sh" apply
