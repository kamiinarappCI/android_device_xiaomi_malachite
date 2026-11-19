#!/bin/sh
# Exercise ksu-module/malachite-performance against scratch sysfs files, a
# fake getprop and stand-ins for the KernelSU installer functions. Run with a
# POSIX shell (dash is closest to KernelSU's ash); needs sha256sum and awk.
set -u
SRC=$(cd "$(dirname "$0")/../ksu-module/malachite-performance" && pwd)
RELEASE_JSON=${RELEASE_JSON:?set RELEASE_JSON to the release powerhint.json}
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1  (want [$3] got [$2])"; fi; }

# setup <running fingerprint> <vendor powerhint file>
setup() {
  W=$(mktemp -d)
  M=$W/module; mkdir -p "$M" "$W/bin" "$W/prev"
  cp -r "$SRC/." "$M/"
  printf '#!/bin/sh\ncase "$1" in\n  ro.product.device) echo malachite ;;\n  ro.build.fingerprint) echo "%s" ;;\n  sys.boot_completed) echo 1 ;;\nesac\n' "$1" > "$W/bin/getprop"
  printf '#!/bin/sh\n:\n' > "$W/bin/sleep"
  printf '#!/bin/sh\necho "I libperfmgr: 1 AdpfConfigs parsed successfully"\n' > "$W/bin/logcat"
  printf '#!/bin/sh\necho "HAL Support: true"\n' > "$W/bin/dumpsys"
  chmod +x "$W/bin/"*
  C=$W/cpu
  for p in 0 4; do
    mkdir -p "$C/cpufreq/policy$p"
    echo "sugov_ext conservative powersave performance schedutil" > "$C/cpufreq/policy$p/scaling_available_governors"
    echo schedutil > "$C/cpufreq/policy$p/scaling_governor"
  done
  mkdir -p "$C/cpuqos"; : > "$C/cpuqos/cpuqos_boot_complete"
  mkdir -p "$W/cpuctl/camera-daemon" "$W/cpuctl/nnapi-hal"
  echo 70.00 > "$W/cpuctl/camera-daemon/cpu.uclamp.min"
  echo 90.00 > "$W/cpuctl/nnapi-hal/cpu.uclamp.min"
  echo 128 > "$W/ceiling"
  cp "$2" "$W/powerhint.json"
  export PATH="$W/bin:$PATH" PERF_CPU="$C" PERF_CEILING="$W/ceiling" PERF_CPUCTL="$W/cpuctl" \
    PERF_LOG="$W/log" PERF_TARGET="$W/powerhint.json" PERF_PREV="$W/prev"
}
install() {
  ( MODPATH=$M
    ui_print() { echo "$*" >> "$W/install.log"; }
    abort() { echo "$*" >> "$W/install.log"; exit 1; }
    set_perm() { :; }
    . "$M/customize.sh" ) && echo ok || echo aborted
}
boot() { sh "$M/post-fs-data.sh"; [ -e "$M/disable" ] || sh "$M/service.sh"; }
gov() { echo "$(cat "$C/cpufreq/policy0/scaling_governor")/$(cat "$C/cpufreq/policy4/scaling_governor")"; }
ceil() { cat "$W/ceiling"; }

setup "build/A" "$RELEASE_JSON"
check "release build: installs"                 "$(install)" "ok"
check "release build: ADPF enabled"             "$([ -e "$M/adpf_enabled" ] && [ -f "$M/system/vendor/etc/powerhint.json" ] && [ -f "$M/sepolicy.rule" ] && echo yes)" "yes"
boot
check "boot: sugov_ext on both clusters"        "$(gov)" "sugov_ext/sugov_ext"
check "boot: cpuqos written"                    "$(cat "$C/cpuqos/cpuqos_boot_complete")" "1"
check "boot: camera and NNAPI back to 12.5"     "$(cat "$W/cpuctl/camera-daemon/cpu.uclamp.min")/$(cat "$W/cpuctl/nnapi-hal/cpu.uclamp.min")" "12.5/12.5"
check "boot: ceiling lifted"                    "$(ceil)" "1024"
check "boot: HAL result logged"                 "$(grep -c 'AdpfConfigs parsed successfully' "$W/log")" "1"
sh "$M/action.sh" > /dev/null
check "action: switches to schedutil"           "$(gov)" "schedutil/schedutil"
echo 128 > "$W/ceiling"; echo schedutil > "$C/cpufreq/policy0/scaling_governor"; boot
check "action choice survives reboot"           "$(gov)" "schedutil/schedutil"
sh "$M/action.sh" > /dev/null
check "action again: back to sugov_ext"         "$(gov)" "sugov_ext/sugov_ext"
rm -rf "$W"

setup "build/A" "$RELEASE_JSON"
printf '{"Nodes": [], "Actions": []}\n' > "$W/powerhint.json"
check "other build: still installs"             "$(install)" "ok"
check "other build: no overlay, no rules"       "$([ -e "$M/system" ] || [ -e "$M/sepolicy.rule" ] || [ -e "$M/adpf_enabled" ] || echo clean)" "clean"
boot
check "other build: governor still applied"     "$(gov)" "sugov_ext/sugov_ext"
check "other build: ceiling untouched"          "$(ceil)" "128"
check "other build: camera boost untouched"     "$(cat "$W/cpuctl/camera-daemon/cpu.uclamp.min")" "70.00"
rm -rf "$W"

setup "build/A" "$RELEASE_JSON"
cp "$SRC/system/vendor/etc/powerhint.json" "$W/powerhint.json"
touch "$W/prev/use_schedutil"
check "upgrade over mounted overlay: installs"  "$(install)" "ok"
check "upgrade: ADPF kept"                      "$([ -e "$M/adpf_enabled" ] && echo yes)" "yes"
check "upgrade: governor choice kept"           "$([ -e "$M/use_schedutil" ] && echo yes)" "yes"
rm -rf "$W"

setup "build/A" "$RELEASE_JSON"
printf 'corrupt' > "$M/system/vendor/etc/powerhint.json"
check "corrupt overlay: refuses"                "$(install)" "aborted"
rm -rf "$W"

setup "build/A" "$RELEASE_JSON"
install > /dev/null
printf '#!/bin/sh\ncase "$1" in\n  ro.build.fingerprint) echo build/B ;;\n  sys.boot_completed) echo 1 ;;\nesac\n' > "$W/bin/getprop"
boot
check "ROM changed: skip mount and disable"     "$([ -e "$M/skip_mount" ] && [ -e "$M/disable" ] && echo yes)" "yes"
check "ROM changed: nothing applied"            "$(gov)/$(ceil)" "schedutil/schedutil/128"
check "ROM changed: reason logged"              "$(grep -c 'ROM changed' "$W/log")" "1"
rm -rf "$W"

setup "build/A" "$RELEASE_JSON"
install > /dev/null
echo 90.00 > "$W/cpuctl/nnapi-hal/cpu.uclamp.min"
chmod 444 "$W/cpuctl/nnapi-hal/cpu.uclamp.min"
boot
check "boost write fails: ceiling kept"         "$(ceil)" "128"
rm -rf "$W"

echo "malachite-performance: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
