#!/system/bin/sh
#
# malachite performance: MediaTek governor, cache QoS and ADPF
#
# Applies three changes from the device tree's noam/lineage-23.2 branch to an
# installed build:
#
#   service.sh     after boot: sugov_ext governor, cpuqos on, and (with ADPF)
#                  sched_util_clamp_min 1024
#   sepolicy.rule  lets the power HAL set uclamp on the threads of an ADPF
#                  session, as Pixel's policy does
#   system/        /vendor/etc/powerhint.json with an AdpfConfig section, and
#                  the release's 40-100% boosts written as the 12.5% they ran
#                  at under the old ceiling (tools/make_perf_module.py)
#
# The powerhint.json overlay is a whole-file replacement built from the
# 11 September 2026 release, so ADPF is only installed when the phone's file
# is that exact one. The governor and cpuqos apply on any build it is
# installed on; after a ROM update post-fs-data.sh disables the module until
# it is reinstalled.

TARGET=${PERF_TARGET:-/vendor/etc/powerhint.json}
RELEASE_SHA=701c21b624eeddc1a9ab2b459a455e1439f1aa3033eaa8d312ed2cdb0c39824c
MODULE_SHA=5c69e42e4e3ee4a57bc061692e79411c700b91e3d01fadb9426f4a8baa13afb2
FALLBACK_CTX=u:object_r:vendor_configs_file:s0
CPU=${PERF_CPU:-/sys/devices/system/cpu}
PREV=${PERF_PREV:-/data/adb/modules/malachite_performance}

ui_print " "
ui_print "  malachite performance: MediaTek governor, cache QoS and ADPF"
ui_print " "

DEVICE=$(getprop ro.product.device)
ui_print "- Device: $DEVICE"
if [ "$DEVICE" != "malachite" ]; then
  abort "! This module targets malachite only. Aborting."
fi

# --- Governor and cpuqos: report what the kernel offers ---------------------
if grep -qw sugov_ext "$CPU/cpufreq/policy0/scaling_available_governors" 2>/dev/null; then
  ui_print "- sugov_ext governor: available"
else
  ui_print "- sugov_ext governor: not offered by this kernel, schedutil stays"
fi
if [ -e "$CPU/cpuqos/cpuqos_boot_complete" ]; then
  ui_print "- cpuqos: available"
else
  ui_print "- cpuqos: not present, skipped"
fi

# Keep an earlier governor choice made with the Action button.
if [ -f "$PREV/use_schedutil" ]; then
  touch "$MODPATH/use_schedutil"
  ui_print "- Keeping your earlier choice: schedutil"
fi

# --- ADPF --------------------------------------------------------------------
OVERLAY="$MODPATH/system/vendor/etc/powerhint.json"
HAVE=$(sha256sum "$TARGET" 2>/dev/null | awk '{print $1}')
case "$HAVE" in
  "$RELEASE_SHA")
    ADPF=1
    ui_print "- powerhint.json matches the 11 September release"
    ;;
  "$MODULE_SHA")
    # An earlier install is mounted over the file; the release's copy is
    # underneath, untouched.
    ADPF=1
    ui_print "- Existing install detected, upgrading in place"
    ;;
  *)
    ADPF=0
    ui_print "!"
    ui_print "! powerhint.json is from a different build than the"
    ui_print "! one this module was made for:"
    ui_print "!   expected: $RELEASE_SHA"
    ui_print "!   found:    ${HAVE:-unreadable}"
    ui_print "! ADPF is left off. The governor and cpuqos still apply."
    ui_print "!"
    ;;
esac

if [ "$ADPF" = 1 ]; then
  SHIPPED=$(sha256sum "$OVERLAY" 2>/dev/null | awk '{print $1}')
  if [ "$SHIPPED" != "$MODULE_SHA" ]; then
    abort "! Shipped powerhint.json is corrupt. Refusing to install."
  fi
  CTX=$(ls -Z "$TARGET" 2>/dev/null | awk '{print $1}')
  case "$CTX" in
    u:object_r:*) ;;
    *) CTX="$FALLBACK_CTX"
       ui_print "- Could not read stock context, using default" ;;
  esac
  set_perm "$OVERLAY" 0 0 0644 "$CTX"
  touch "$MODPATH/adpf_enabled"
  ui_print "- ADPF: on (powerhint.json overlay, SELinux rules)"
else
  rm -rf "$MODPATH/system" "$MODPATH/sepolicy.rule"
fi

for f in post-fs-data.sh service.sh action.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

# post-fs-data.sh stands the module down if the ROM changes, so the overlay
# never replaces a newer build's powerhint.json.
getprop ro.build.fingerprint > "$MODPATH/installed_fingerprint"
ui_print "- Pinned to: $(cat "$MODPATH/installed_fingerprint")"

ui_print " "
ui_print "- Installed. Reboot to apply."
ui_print "- Status after boot: /data/local/tmp/malachite_performance.log"
ui_print "- Action button in the KernelSU app: switch between"
ui_print "  sugov_ext and schedutil. Takes effect immediately and"
ui_print "  is remembered."
ui_print "- To undo everything, remove the module and reboot."
ui_print " "
