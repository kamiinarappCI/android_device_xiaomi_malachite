#!/system/bin/sh
# Shared by service.sh and action.sh.
NODE=/sys/class/power_supply/battery/charger_partition_poweroffmode
STATE=/data/adb/malachite_offmode
LOG=$STATE/log.txt
OUT=/sdcard/Download/malachite_offmode.txt
mkdir -p "$STATE"

up() { cut -d. -f1 /proc/uptime; }
log() { echo "$(date '+%m-%d %H:%M:%S') up=$(up)s $*" >> "$LOG"; }
flag() { cat "$NODE" 2>/dev/null || echo unreadable; }
publish() { [ -d /sdcard/Download ] && cp "$LOG" "$OUT" 2>/dev/null; }
