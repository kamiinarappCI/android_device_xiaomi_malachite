#!/bin/bash
# Follow the newest build log of a day until the signed OTA exists or the build
# fails, printing the ninja progress every 30 s. From Windows (cmd or PowerShell):
#
#   wsl bash /mnt/e/LineageOS-23.2-Malachite/tools/build_status.sh [YYYYMMDD]
#
# The day defaults to today; the log is ~/android/build-<day>-<HHMM>.log written
# by build_malachite.sh, which ends with package_build.sh's READY line.
day=${1:-$(date +%Y%m%d)}
while :; do
  log=$(ls -t ~/android/build-"$day"-*.log 2>/dev/null | head -1)
  if [ -z "$log" ]; then
    echo "$(date +%H:%M) product configuration..."
    sleep 30
    continue
  fi
  progress=$(tail -c 4000 "$log" | tr '\r' '\n' | grep -oE '^\[ *[0-9]+% [0-9]+/[0-9]+( [0-9hms]+ remaining)?\]' | tail -1)
  step=$(grep -E '^(phase: |mac_permissions signer check|Shared-UID signer check)' "$log" | tail -1)
  echo "$(date +%H:%M) ${progress:-starting}${step:+ | $step}"
  if grep -q '^READY: ' "$log"; then
    echo "DONE: $(grep '^READY: ' "$log" | tail -1 | cut -c8-)"
    break
  fi
  if grep -q 'copy to E: failed' "$log"; then
    echo "FAILED: signed, but the copy to E:\\Android\\Malachite\\builds failed its checksum"
    break
  fi
  if grep -qE 'build exit: [1-9]|^FAILED:|#### failed' "$log"; then
    echo "FAILED:"
    grep -E '^FAILED:|build exit|#### failed' "$log" | tail -3
    break
  fi
  sleep 30
done
