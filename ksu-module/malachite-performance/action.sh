#!/system/bin/sh
# Action button: switch the CPU governor between sugov_ext and schedutil,
# live, and remember the choice for later boots. service.sh calls this with
# --apply to set the remembered governor without switching.
MODDIR=${0%/*}
CPU=${PERF_CPU:-/sys/devices/system/cpu}
CEILING=${PERF_CEILING:-/proc/sys/kernel/sched_util_clamp_min}

if [ "$1" != "--apply" ]; then
  if [ -f "$MODDIR/use_schedutil" ]; then
    rm -f "$MODDIR/use_schedutil"
  else
    touch "$MODDIR/use_schedutil"
  fi
fi

WANT=sugov_ext
[ -f "$MODDIR/use_schedutil" ] && WANT=schedutil

for p in 0 4; do
  pol=$CPU/cpufreq/policy$p
  if grep -qw "$WANT" "$pol/scaling_available_governors" 2>/dev/null; then
    echo "$WANT" > "$pol/scaling_governor"
  fi
  echo "policy$p governor: $(cat "$pol/scaling_governor")"
done

if [ "$1" != "--apply" ]; then
  echo "uclamp.min ceiling: $(cat "$CEILING")"
  echo "Kept for later boots. Press again to switch back."
fi
