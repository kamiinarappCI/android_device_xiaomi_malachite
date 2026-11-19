#!/system/bin/sh
# Shared by post-fs-data.sh, service.sh and action.sh.
#
# State lives outside the module directory so an update keeps it:
#   mode     next restart to try: kpoc, then charger, then none
#   pending  "<mode> <epoch seconds>" while a restart is being tested
STATE=${OFFMODE_STATE:-/data/adb/malachite_offmode_test}
LOG=${OFFMODE_LOG:-/data/local/tmp/malachite_offmode_test.log}
REBOOT=${OFFMODE_REBOOT:-/system/bin/reboot}
# A restart that is not honoured comes straight back into Android, usually
# within a minute. Testers are asked to leave the phone off for 5 minutes.
QUICK=180

mkdir -p "$STATE"

log() {
  echo "$(date '+%F %T') $*" >> "$LOG"
}

mode() {
  m=$(cat "$STATE/mode" 2>/dev/null)
  echo "${m:-kpoc}"
}

next_mode() {
  case "$1" in
    kpoc) echo charger ;;
    *) echo none ;;
  esac
}

# Restart into a charging mode and remember when, so the next boot can tell
# whether the phone stayed off.
restart_into() {
  echo "$1 $(date +%s)" > "$STATE/pending"
  sync
  log "RESTART: reboot $1"
  $REBOOT "$1"
}

# Called early on every boot. Returns 0 if a test was pending: this boot
# then never restarts again, so the module cannot loop.
check_pending() {
  [ -f "$STATE/pending" ] || return 1
  read -r tried at < "$STATE/pending"
  rm -f "$STATE/pending"
  took=$(( $(date +%s) - ${at:-0} ))
  if [ "$took" -lt "$QUICK" ]; then
    new=$(next_mode "$tried")
    echo "$new" > "$STATE/mode"
    log "RESULT: '$tried' NOT honoured: back in Android ${took}s after the restart."
    if [ "$new" = none ]; then
      log "RESULT: neither kpoc nor charger kept the phone off."
    else
      log "        Next test will use '$new'."
    fi
  else
    log "RESULT: '$tried' probably honoured: phone stayed off ${took}s before this boot."
    log "        (Confirm: did the charging screen show and the phone stay off?)"
  fi
  return 0
}
