#!/usr/bin/env bash
# Pull everything useful off the phone after a bootloop, freeze or reboot.
# Run on the PC (Git Bash, Linux or macOS) with the phone on USB:
#
#   bash tools/collect_logs.sh            # waits for adb, then collects
#
# Works without root. adb answers once the phone has decrypted /data during
# boot; the PC's key authorised on the old ROM carries over a dirty flash.
# Output: evidence/<date>-<time>/ (gitignored: it holds device identifiers).
set -u

out="$(dirname "$0")/../evidence/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$out" || exit 1
echo "Saving to $out"

echo "Waiting for adb (Ctrl+C to give up)..."
adb wait-for-device || exit 1

run() { # name, command...
  local name=$1; shift
  echo "  $name"
  "$@" > "$out/$name" 2>&1
}

run getprop.txt           adb shell getprop
run boot-state.txt        adb shell 'echo "boot_completed=$(getprop sys.boot_completed)"; echo "bootanim=$(getprop init.svc.bootanim)"; echo "selinux=$(getenforce)"; uptime'
run logcat-all.txt        adb logcat -b all -d -v threadtime -v uid
run logcat-kernel.txt     adb logcat -b kernel -d -v threadtime
run logcat-crash.txt      adb logcat -b crash -d -v threadtime
# Logs from earlier boots, kept by logcatd (userdebug diagnostics block).
run logcat-persisted.txt  adb shell logpersist.cat
run avc-denials.txt       adb shell 'logcat -b all -d | grep -E "avc: +denied"'
run services.txt          adb shell 'getprop | grep -E "init\.svc\.|boot"'

echo "  bugreport (takes a few minutes; includes tombstones, ANRs, dmesg)"
adb bugreport "$out/bugreport.zip" > "$out/bugreport.log" 2>&1

echo "Done. Largest files:"
ls -lS "$out" | head -12
