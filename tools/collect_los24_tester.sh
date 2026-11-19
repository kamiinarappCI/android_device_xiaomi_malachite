#!/system/bin/sh
# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# Run interactively from Termux: su -c 'sh /sdcard/Download/collect_los24_tester.sh'
# Or after adb root: adb shell -t sh /data/local/tmp/collect_los24_tester.sh adb

if [ "$(id -u)" != 0 ]; then
    echo "Run adb root first, or run this script with su from Termux."
    exit 1
fi

capture_terminal=Termux
if [ "$1" = adb ]; then
    capture_terminal="the PC terminal"
fi
capture_name=${2:-"los24-capture-$(date +%Y%m%d-%H%M%S)"}
case "$capture_name" in
    ''|*[!a-zA-Z0-9_-]*) echo "Invalid capture name."; exit 1 ;;
esac
capture_dir="/sdcard/Download/$capture_name"
mkdir -p "$capture_dir" || exit 1
previous_log_tag=$(getprop log.tag)
capture_log_pid=
capture_trace_pid=

restore_capture() {
    setprop log.tag "$previous_log_tag"
    if [ -n "$capture_log_pid" ]; then
        kill "$capture_log_pid" 2>/dev/null
        wait "$capture_log_pid" 2>/dev/null
        capture_log_pid=
    fi
    if [ -n "$capture_trace_pid" ]; then
        kill -INT "$capture_trace_pid" 2>/dev/null
        wait "$capture_trace_pid" 2>/dev/null
        capture_trace_pid=
    fi
}
trap restore_capture 0
trap 'exit 1' 1 2 15

mark_capture() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$capture_dir/steps.txt"
    log -p i -t MalachiteCapture "$*"
}

wait_capture() {
    echo
    echo "$*"
    echo "Return to $capture_terminal and press Enter when finished."
    read -r capture_reply || exit 1
}

{
    date
    uptime
    uname -a
    for capture_prop in ro.build.fingerprint ro.build.version.incremental \
        ro.build.version.release ro.build.version.sdk ro.lineage.version \
        ro.boot.camera.config ro.product.marketname ro.product.device \
        ro.malachite.source.device ro.malachite.source.vendor ro.malachite.source.kernel \
        persist.vendor.sys.fp.vendor persist.sys.battery_saver_cpu_cap \
        vendor.powerhal.battery_saver log.tag persist.log.tag; do
        printf '%s=' "$capture_prop"
        getprop "$capture_prop"
    done
    getprop | grep '^\[ro.boottime\.'
    settings get global animator_duration_scale
    settings get global low_power
    getenforce
} > "$capture_dir/build-and-boot.txt" 2>&1
logcat -b events -d -v threadtime > "$capture_dir/events-before-test.txt" 2>&1

# This volatile fallback overrides a global persist.log.tag=I. It cannot override
# tag-specific thresholds or debug statements compiled out of vendor libraries.
setprop log.tag V
logcat -b all -v threadtime '*:V' > "$capture_dir/logcat.txt" 2>&1 &
capture_log_pid=$!
mark_capture "START"

mark_capture "FOD_AFTER_PIN_BEGIN"
wait_capture "Unlock using PIN/password (not fingerprint). Open the affected payment app and try fingerprint authentication 2-3 times."
mark_capture "FOD_AFTER_PIN_END"
mark_capture "FOD_AFTER_FINGERPRINT_UNLOCK_BEGIN"
wait_capture "Lock the phone. Unlock using fingerprint. Reopen the same app and try fingerprint authentication again."
mark_capture "FOD_AFTER_FINGERPRINT_UNLOCK_END"

echo
echo "Next: have MiCamera ready in normal Photo mode."
echo "After pressing Enter, a 60-second performance trace starts."
echo "During that minute: take a normal photo, take an Ultra HD photo with 200MP selected, then enter Long Exposure."
echo "Let a freeze or crash happen. Do not force-stop the camera."
read -r capture_reply || exit 1
mark_capture "CAMERA_SEQUENCE_BEGIN"
perfetto -o "$capture_dir/camera.perfetto-trace" -t 60s \
    sched freq idle am wm gfx view camera input binder_driver \
    > "$capture_dir/perfetto-status.txt" 2>&1 &
capture_trace_pid=$!
wait_capture "Run the three camera steps now. Note which step freezes/crashes, and roughly how long it takes."
mark_capture "CAMERA_SEQUENCE_END"
echo "Waiting for the performance trace to finish (at most 60 seconds)..."
wait "$capture_trace_pid" 2>/dev/null
capture_trace_pid=

echo "Collecting camera, power and crash state..."
dumpsys -t 20 media.camera > "$capture_dir/camera-dump.txt" 2>&1
dumpsys -t 15 android.hardware.power.IPower/default > "$capture_dir/power-hal.txt" 2>&1
dumpsys -t 15 thermalservice > "$capture_dir/thermal.txt" 2>&1
dumpsys -t 15 battery > "$capture_dir/battery.txt" 2>&1
dumpsys -t 15 biometric > "$capture_dir/biometric.txt" 2>&1
dumpsys -t 15 fingerprint > "$capture_dir/fingerprint.txt" 2>&1
dumpsys -t 15 activity exit-info com.android.camera > "$capture_dir/camera-exits.txt" 2>&1
dmesg > "$capture_dir/kernel.txt" 2>&1
{
    date
    for capture_policy in /sys/devices/system/cpu/cpufreq/policy*; do
        echo "$capture_policy"
        for capture_node in scaling_governor scaling_min_freq scaling_max_freq scaling_cur_freq; do
            printf '%s=' "$capture_node"
            cat "$capture_policy/$capture_node"
        done
    done
    ls -lt /sdcard/DCIM/Camera | head -12
} > "$capture_dir/end-state.txt" 2>&1
mark_capture "REPRODUCTION_FINISHED"
restore_capture

echo "Generating Android bug report. This can take several minutes."
bugreportz -p > "$capture_dir/bugreport-status.txt" 2>&1
capture_report=$(sed -n 's/^OK://p' "$capture_dir/bugreport-status.txt" | tail -1 | tr -d '\r')
if [ -n "$capture_report" ] && [ -f "$capture_report" ]; then
    cp "$capture_report" "$capture_dir/bugreport.zip"
else
    echo "Android bug report failed; the other captures are still saved."
fi

echo "Packing the capture..."
if tar -czf "/sdcard/Download/$capture_name.tar.gz" -C /sdcard/Download "$capture_name"; then
    echo
    echo "DONE: /sdcard/Download/$capture_name.tar.gz"
else
    echo "Packing failed. Send the folder: $capture_dir"
fi
echo "Send privately, together with the two original photos as files."
echo "Say which camera mode crashed, whether 200MP was selected, and whether the second app fingerprint attempt worked."
