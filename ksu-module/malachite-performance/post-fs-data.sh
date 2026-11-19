#!/system/bin/sh
# Runs before KernelSU mounts this module's system/ files. The powerhint.json
# overlay is a whole-file copy of one build's table, so on any other build it
# must not be mounted: skip_mount stops this boot's mount, disable keeps the
# module off afterwards.
MODDIR=${0%/*}
LOG=${PERF_LOG:-/data/local/tmp/malachite_performance.log}

[ -f "$MODDIR/installed_fingerprint" ] || exit 0
NOW=$(getprop ro.build.fingerprint)
WAS=$(cat "$MODDIR/installed_fingerprint")
if [ "$NOW" != "$WAS" ]; then
  touch "$MODDIR/skip_mount" "$MODDIR/disable"
  {
    echo "$(date): ROM changed, module disabled before mounting"
    echo "  installed on: $WAS"
    echo "  running now : $NOW"
    echo "  Reinstall the module to re-check this build."
  } >> "$LOG" 2>/dev/null
fi
