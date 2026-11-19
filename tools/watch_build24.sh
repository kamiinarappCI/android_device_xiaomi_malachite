#!/bin/bash
# Wait for a LineageOS 24.0 build started after a given time, then print one line
# saying how it ended. Meant to run in the background next to build_lineage24.sh.
#
#   bash /mnt/e/LineageOS-23.2-Malachite/tools/watch_build24.sh "2026-10-27 09:30:00"
#
# Ends with READY (zip packaged), FAILED (first errors from the log), STALLED (no
# log output for 90 min) or NO LOG (build_malachite.sh never started). If C: falls
# under 12 GB free it stops the build first, so Windows never runs out of space
# (the build disk C:\WSL\MalachiteBuild\ext4.vhdx grows into C:).
start=$(date -d "${1:?start time}" +%s)
L=
while true; do
  cfree=$(df -BG --output=avail /mnt/c | tail -1 | tr -dc 0-9)
  if [ -n "$cfree" ] && [ "$cfree" -lt 12 ]; then
    pkill -f build_lineage24.sh; pkill -f build_malachite.sh; pkill -INT -f soong_ui
    sleep 20; pkill -f soong_ui; pkill -f siso
    echo "DISK: C: down to ${cfree} GB free, build stopped. Log: $L"; exit 0
  fi
  if [ -z "$L" ]; then
    for f in $(ls -t ~/android/build-*.log 2>/dev/null | head -3); do
      [ "$(stat -c %Y "$f")" -ge "$start" ] && head -3 "$f" | grep -q "phase: start" && { L=$f; break; }
    done
  fi
  if [ -n "$L" ]; then
    if grep -q '^READY: ' "$L"; then
      echo "READY: $L (C: ${cfree} GB free)"; grep '^READY: ' "$L" | tail -1; exit 0
    fi
    if grep -qE 'build exit: [1-9]|#### failed|copy to E: failed' "$L"; then
      echo "FAILED: $L (C: ${cfree} GB free)"
      grep -n -E '^FAILED: |[^a-z]error: |Killed|build exit' "$L" | grep -v thiserror | head -8 | cut -c1-400
      exit 0
    fi
    age=$(( $(date +%s) - $(stat -c %Y "$L") ))
    [ "$age" -gt 5400 ] && { echo "STALLED: no log output for 90 min: $L"; tail -3 "$L" | cut -c1-300; exit 0; }
  elif [ $(( $(date +%s) - start )) -gt 1800 ]; then
    echo "NO LOG: no build log 30 min after start"; ls -t ~/android/build-*.log | head -2; exit 0
  fi
  sleep 60
done
