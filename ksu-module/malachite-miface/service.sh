#!/system/bin/sh
# Starts mifaced the way stock's miface.rc does (user and group system, AOSP's
# face HAL domain via sepolicy.rule), restarts it if it exits, and logs the
# result once Android has booted. KernelSU cannot add init services, so this
# script stands in for init.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

[ -f "$MODDIR/disable" ] && exit 0

echo "$(date '+%F %T') malachite miface $(grep '^version=' "$MODDIR/module.prop")" > "$LOG"
log "ROM: $(getprop ro.lineage.display.version)"

if [ ! -x "$HAL" ]; then
  log "FAIL: $HAL not visible, the module's files were not mounted"
  exit 0
fi

# In case post-mount.sh did not run (older KernelSU).
refresh_vintf

# Same start state as an init service: root cpuset and cpu cgroups (all cores,
# no background cap), not this script's.
for cg in /dev/cpuset /dev/cpuctl; do
  [ -w "$cg/cgroup.procs" ] && echo $$ > "$cg/cgroup.procs" 2>/dev/null
done

run_hal() {
  if [ -x "$BB" ] && "$BB" --list 2>/dev/null | grep -qx setuidgid; then
    "$BB" setuidgid system "$HAL" </dev/null >/dev/null 2>&1
  else
    su 1000 -c "exec $HAL" </dev/null >/dev/null 2>&1
  fi
}

(
  starts=0
  window=$(date +%s)
  while true; do
    run_hal
    rc=$?
    now=$(date +%s)
    if [ $((now - window)) -gt 120 ]; then
      starts=0
      window=$now
    fi
    starts=$((starts + 1))
    log "mifaced exited ($rc)"
    # Same budget as a crashing init service before giving up.
    if [ "$starts" -ge 5 ]; then
      log "FAIL: mifaced exited 5 times in 2 minutes; not restarting until next boot"
      break
    fi
    sleep 2
  done
) &

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 5
done
sleep 15

pid=$(pidof mifaced)
log "mifaced pid: ${pid:-not running}"
[ -n "$pid" ] && log "mifaced context: $(cat /proc/$pid/attr/current 2>/dev/null) uid: $(awk '/^Uid:/ {print $2}' /proc/$pid/status)"
log "IFace/default: $(service check android.hardware.biometrics.face.IFace/default 2>&1)"
log "face sensors: $(dumpsys face 2>/dev/null | grep -m3 -iE 'sensor|strength|enrolled' | tr '\n' ' ')"

# ParanoidSense: gone if the whiteouts worked; otherwise keep its overlays off.
if pm path "$SENSE_PKG" >/dev/null 2>&1; then
  log "ParanoidSense still installed (no whiteout support); disabling its overlays"
  for o in $SENSE_OVERLAYS; do
    cmd overlay disable "$o" >/dev/null 2>&1 && log "  overlay off: $o"
  done
else
  log "ParanoidSense: removed"
fi

denials=$(logcat -d -b all 2>/dev/null | grep 'avc:  denied' | grep -cE 'hal_face_default|scontext=u:r:cameraserver.*hal_face')
log "SELinux denials for the HAL so far: $denials"
