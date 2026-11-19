#!/system/bin/sh
# Applies the runtime settings once the ROM has finished its own boot actions,
# which switch the governor back to schedutil at sys.boot_completed.
MODDIR=${0%/*}
LOG=${PERF_LOG:-/data/local/tmp/malachite_performance.log}
CPU=${PERF_CPU:-/sys/devices/system/cpu}
CEILING=${PERF_CEILING:-/proc/sys/kernel/sched_util_clamp_min}
CPUCTL=${PERF_CPUCTL:-/dev/cpuctl}

log() { echo "$*" >> "$LOG" 2>/dev/null; }

# Late fallback for the ROM-change guard in post-fs-data.sh.
if [ -f "$MODDIR/installed_fingerprint" ] &&
   [ "$(getprop ro.build.fingerprint)" != "$(cat "$MODDIR/installed_fingerprint")" ]; then
  touch "$MODDIR/disable"
  exit 0
fi

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done
sleep 20

echo "$(date): malachite performance" > "$LOG" 2>/dev/null

# cpuqos_v3.ko keeps L3 partitioning disabled until this is written.
if echo 1 > "$CPU/cpuqos/cpuqos_boot_complete" 2>/dev/null; then
  log "cpuqos: enabled"
else
  log "cpuqos: not available"
fi

sh "$MODDIR/action.sh" --apply >> "$LOG" 2>&1

# ADPF: lift the uclamp.min ceiling so sessions can size their threads.
# The release writes 70 and 90 for these two groups; bring them to the 12.5
# they ran at under the old ceiling first, and keep the ceiling if either
# write fails.
if [ -f "$MODDIR/adpf_enabled" ]; then
  ok=1
  for g in camera-daemon nnapi-hal; do
    f=$CPUCTL/$g/cpu.uclamp.min
    [ -e "$f" ] || continue
    echo 12.5 > "$f" 2>/dev/null
    awk 'NR == 1 && $1 ~ /^[0-9.]+$/ { v = $1; n = 1 } END { exit !(n && v + 0 <= 12.5) }' \
      "$f" 2>/dev/null || ok=0
    log "$g uclamp.min: $(cat "$f" 2>/dev/null)"
  done
  if [ "$ok" = 1 ]; then
    echo 1024 > "$CEILING"
  fi
  log "sched_util_clamp_min: $(cat "$CEILING")"
  log "power HAL: $(logcat -d -b main 2>/dev/null |
    grep -m1 -E 'AdpfConfigs parsed successfully|No AdpfConfig section|Failed to read AdpfConfig')"
  log "performance_hint: $(dumpsys performance_hint 2>/dev/null | grep -m2 -iE 'support|rate' | tr '\n' ' ')"
else
  log "ADPF: off (powerhint.json is from another build)"
fi
