#!/usr/bin/env bash
# Everything to check on the phone before dirty-flashing our build over
# chara's LineageOS. Run on the PC (Git Bash or Linux) with the phone booted
# and USB debugging on:
#
#   bash tools/preflash_check.sh
#
# Read-only: nothing on the phone is written except the signer inventory
# script and its report in /data/local/tmp. With root (KernelSU: allow Shell
# in the manager when the phone asks) it also copies the boot images of both
# slots to the PC and reads the super partition layout.
#
# Output: evidence/<date>-preflash/ (gitignored: device identifiers and
# partition images). report.txt holds the verdicts.
set -u
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'   # keep /dev/... paths intact in Git Bash

here=$(cd "$(dirname "$0")" && pwd)
out="$here/../evidence/$(date +%Y-%m-%d-%H%M%S)-preflash"
mkdir -p "$out/images" || exit 1
report="$out/report.txt"
fails=0 warns=0

say()  { echo "$*" | tee -a "$report"; }
pass() { say "  PASS  $*"; }
warn() { say "  WARN  $*"; warns=$((warns + 1)); }
fail() { say "  FAIL  $*"; fails=$((fails + 1)); }
info() { say "  info  $*"; }
prop() { adb shell getprop "$1" | tr -d '\r'; }
rsh()  { adb shell "su -c '$1'" 2>/dev/null | tr -d '\r'; }   # root shell
# The value in the ROM's own build.prop files. Props that apps see can be
# rewritten at runtime by spoofing modules (Play Integrity Fix and the like).
fprop() {
  adb shell "grep -h -m1 '^$1=' /system/build.prop /product/etc/build.prop /system_ext/etc/build.prop /vendor/build.prop 2>/dev/null" |
    head -1 | tr -d '\r' | cut -d= -f2-
}
# adb.exe is a Windows program: give it Windows paths when running in Git Bash.
host() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }

# Patch level from a boot or init_boot image header: os_version sits at
# offset 16 in header v3/v4 and at 44 before that; the low 11 bits are
# (year - 2000) << 4 | month.
header_patch() {
  local ver os
  [ "$(head -c 8 "$1" | tr -d '\0')" = "ANDROID!" ] || { echo "no header"; return; }
  ver=$(od -An -tu4 -j40 -N4 "$1" | tr -d ' ')
  if [ "$ver" -ge 3 ]; then os=$(od -An -tu4 -j16 -N4 "$1" | tr -d ' ')
  else os=$(od -An -tu4 -j44 -N4 "$1" | tr -d ' '); fi
  printf "%04d-%02d\n" $(( ((os & 0x7ff) >> 4) + 2000 )) $(( os & 0xf ))
}

echo "Saving to $out"
echo "Waiting for adb (Ctrl+C to give up)..."
adb wait-for-device || exit 1
adb shell getprop > "$out/getprop.txt"

say "malachite pre-flash check  $(date)"
say ""
say "== Phone and ROM"
device=$(prop ro.product.device)
if [ "$device" != malachite ]; then
  fail "this is '$device', not malachite; stopping"
  exit 1
fi
pass "device: malachite ($(prop ro.product.model))"
info "ROM: $(fprop ro.lineage.version) (built $(fprop ro.build.date))"
info "fingerprint: $(fprop ro.build.fingerprint)"
info "kernel: $(adb shell uname -r | tr -d '\r')"
type=$(fprop ro.build.type)
[ "$(prop ro.build.type)" = "$type" ] ||
  info "apps are shown build type '$(prop ro.build.type)' (spoofed by a module); the ROM's is '$type'"
case $type in
  userdebug|eng) pass "build type $type: recovery offers \"Install anyway?\" for our signature" ;;
  *) fail "build type $type: recovery refuses a zip signed with other keys" ;;
esac
info "first API level: $(prop ro.product.first_api_level)"

say ""
say "== Bootloader and slot"
# The bootloader's own value is in /proc/bootconfig (root) or /proc/cmdline;
# ro.boot.* props are commonly spoofed to "green" and "locked".
vbstate=$(rsh "cat /proc/bootconfig /proc/cmdline" | tr ' ' '\n' | tr -d '"' |
  sed -n 's/^androidboot\.verifiedbootstate=//p' | head -1)
[ -n "$vbstate" ] || vbstate=$(rsh "cat /proc/bootconfig" | tr -d '" ' |
  sed -n 's/^androidboot\.verifiedbootstate=//p' | head -1)
if [ -n "$vbstate" ]; then src="bootloader"
else vbstate=$(prop ro.boot.verifiedbootstate); src="props, may be spoofed; allow root to read the bootloader's value"; fi
if [ "$vbstate" = orange ]; then
  pass "bootloader unlocked (verifiedbootstate=orange, from the $src)"
else
  fail "bootloader not shown as unlocked (verifiedbootstate=$vbstate, from the $src): do not flash"
fi
[ "$(prop ro.boot.verifiedbootstate)" = "$vbstate" ] ||
  info "apps are shown verifiedbootstate '$(prop ro.boot.verifiedbootstate)' (spoofed by a module)"
slot=$(prop ro.boot.slot_suffix)
info "running slot: $slot (the update installs to the other one)"
level=$(adb shell dumpsys battery | tr -d '\r' | awk '$1 == "level:" { print $2; exit }')
if [ "${level:-0}" -ge 50 ]; then pass "battery $level%"; else warn "battery ${level:-?}%: charge above 50% first"; fi

say ""
say "== Security patch (a newer one upgrades the TEE's keys; going back can then fail to unlock /data)"
phone_patch=$(fprop ro.build.version.security_patch)
our_patch=${OUR_PATCH:-}
if [ -z "$our_patch" ]; then
  # Our build's value, from the synced source in WSL (release config named in vars).
  q='v=~/android/lineage/vendor/lineage; r=$(sed -n "s/.*=//p" $v/vars/aosp_target_release);
     grep -o "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]" $v/release/flag_values/$r/RELEASE_PLATFORM_SECURITY_PATCH.textproto'
  if command -v wsl >/dev/null 2>&1; then our_patch=$(wsl -e sh -c "$q" 2>/dev/null | tr -d '\r')
  else our_patch=$(sh -c "$q" 2>/dev/null); fi
fi
info "phone: Android $phone_patch, vendor $(fprop ro.vendor.build.security_patch)"
if [ -z "$our_patch" ]; then
  warn "our build's patch level unknown (set OUR_PATCH=YYYY-MM-DD)"
elif [[ "${our_patch:0:7}" > "${phone_patch:0:7}" ]]; then
  warn "ours ($our_patch) is newer than the phone's ($phone_patch): after our build boots once, going back to chara's build may not unlock /data. Rely on the backup, not on rollback"
else
  pass "ours ($our_patch) is not newer than the phone's ($phone_patch)"
fi

say ""
say "== Encryption settings (must match, or /data will not unlock after a dirty flash)"
# Compare with what the build uses: OUR_FSTAB (e.g. the built
# vendor/etc/fstab.mt6878), else the device fork's crdroid-17.0 (the main line
# since 2026-11-10) as the manifest syncs it.
fstab_url=https://raw.githubusercontent.com/malachite-project/android_device_xiaomi_malachite/crdroid-17.0/init/fstab.mt6878
if [ -n "${OUR_FSTAB:-}" ]; then
  ours_fstab="$OUR_FSTAB"
  info "our fstab: $OUR_FSTAB"
elif curl -fsSL "$fstab_url" -o "$out/fstab.ours" 2>/dev/null && [ -s "$out/fstab.ours" ]; then
  ours_fstab="$out/fstab.ours"
  info "our fstab: crdroid-17.0 on GitHub"
else
  echo "cannot fetch $fstab_url; pass OUR_FSTAB=<path>"; exit 1
fi
adb shell cat /vendor/etc/fstab.mt6878 2>/dev/null | tr -d '\r' > "$out/fstab.phone"
[ -s "$out/fstab.phone" ] || rsh "cat /vendor/etc/fstab.mt6878" > "$out/fstab.phone"
# /data and /metadata: filesystem, encryption modes and key location.
fstab_keys() {
  awk '$1 !~ /^#/ && ($2 == "/data" || $2 == "/metadata") {
    n = split($5, f, ",")
    s = $2 " " $3
    for (i = 1; i <= n; i++) if (f[i] ~ /^(fileencryption|metadata_encryption|keydirectory)=/) s = s " " f[i]
    print s
  }' "$1" | sort
}
if [ ! -s "$out/fstab.phone" ]; then
  warn "could not read /vendor/etc/fstab.mt6878 from the phone"
elif [ ! -f "$ours_fstab" ]; then
  warn "our fstab not found: $ours_fstab"
elif diff <(fstab_keys "$out/fstab.phone") <(fstab_keys "$ours_fstab") > "$out/fstab.diff"; then
  pass "same /data and /metadata settings:"
  fstab_keys "$ours_fstab" | sed 's/^/          /' | tee -a "$report"
else
  fail "encryption settings differ (< phone, > ours):"
  sed 's/^/          /' "$out/fstab.diff" | tee -a "$report"
fi
info "crypto: $(prop ro.crypto.state), type $(prop ro.crypto.type)"

say ""
say "== App signatures (the key change)"
adb push "$(host "$here/signer_inventory.sh")" /data/local/tmp/ > /dev/null
adb shell sh /data/local/tmp/signer_inventory.sh > /dev/null
adb pull /data/local/tmp/malachite_signers.txt "$(host "$out")" > /dev/null 2>&1
inv="$out/malachite_signers.txt"
if [ ! -s "$inv" ]; then
  fail "signer inventory did not run"
else
  sec1=$(awk '/^== 1\. /{f=1; next} /^== /{f=0} f' "$inv")
  if echo "$sec1" | grep -qx "  none"; then
    pass "no app in /data is signed with a ROM key"
  else
    fail "apps in /data signed with a ROM key (uninstall their updates first):"
    echo "$sec1" | grep . | tee -a "$report"
  fi
  if grep -q "MIXED SIGNERS" "$inv"; then
    fail "a shared UID already has mixed signers: $(grep "MIXED SIGNERS" "$inv" | awk '{print $1}' | tr '\n' ' ')"
  else
    pass "every shared UID has one signer"
  fi
  sec1b=$(awk '/^== 1b\. /{f=1; next} /^== /{f=0} f' "$inv" | grep -v "^   (" | grep -vx "  none")
  [ -z "$sec1b" ] || info "apps in /data signed with another system key (fine unless it is chara's releasekey): $(echo "$sec1b" | awk '{print $1}' | tr '\n' ' ')"
fi

say ""
say "== Root checks"
if [ "$(rsh "id -u")" != 0 ]; then
  warn "no root for adb shell: allow Shell in the KernelSU manager and rerun for backups and the super layout"
else
  pass "root available"

  say ""
  say "== Backups of both slots (to $out/images)"
  for p in boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor; do
    for s in _a _b; do
      dev=/dev/block/by-name/$p$s
      if [ -z "$(rsh "ls $dev")" ]; then info "$p$s: no such partition"; continue; fi
      img="$out/images/$p$s.img"
      adb exec-out "su -c 'cat $dev'" > "$img"
      want=$(rsh "sha256sum $dev" | awk '{print $1}')
      got=$(sha256sum "$img" | awk '{print $1}')
      if [ -n "$want" ] && [ "$want" = "$got" ]; then
        pass "$p$s  $(stat -c %s "$img") bytes  sha256 matches"
      else
        fail "$p$s  copy does not match the phone (sha256 $got vs $want)"
      fi
    done
  done
  (cd "$out/images" && sha256sum *.img > SHA256SUMS)
  for i in boot_a boot_b init_boot_a init_boot_b; do
    [ -f "$out/images/$i.img" ] || continue
    hp=$(header_patch "$out/images/$i.img")
    case $hp in 2000-00) hp="none (empty or unused)" ;; esac
    info "$i header patch level: $hp"
  done

  say ""
  say "== Super partition (does the old slot survive a sideload?)"
  rsh lpdump > "$out/lpdump.txt"
  # "super: START .. END: NAME (N sectors)" rows; sum each slot.
  read -r size used_a used_b < <(awk '
    /Partition name: super$/ { sup = 1 }
    sup && /Size: [0-9]+ bytes/ { size = $2; sup = 0 }
    /^super: / {
      n = $6; gsub(/\(/, "", n)
      if ($5 ~ /_a(-cow)?$/) a += n * 512
      else if ($5 ~ /_b(-cow)?$/) b += n * 512
    }
    END { printf "%d %d %d\n", size, a, b }' "$out/lpdump.txt")
  gib() { awk -v b="$1" 'BEGIN { printf "%.2f GiB", b / 1073741824 }'; }
  if [ "${size:-0}" -eq 0 ] || [ $((used_a + used_b)) -eq 0 ]; then
    warn "could not read the super layout (see lpdump.txt)"
  else
    if [ "$slot" = _a ]; then cur=$used_a; else cur=$used_b; fi
    info "super $(gib "$size"); slot _a uses $(gib "$used_a"), slot _b $(gib "$used_b")"
    # In recovery, update_engine writes the new slot next to the running one
    # if super has room; otherwise it deletes the running slot's partitions
    # first. Our build is assumed about as large as the current one (+10%).
    if [ $((size - cur)) -ge $((cur + cur / 10)) ]; then
      pass "room for both slots: the running slot should stay bootable (rollback = fastboot set_active ${slot#_})"
    else
      warn "probably no room for both: the sideload will delete this slot's system partitions. Rollback then means sideloading chara's zip, not switching slots"
    fi
  fi
  rsh "snapshotctl dump" > "$out/snapshotctl.txt"
  state=$(grep -m1 "Update state:" "$out/snapshotctl.txt" | sed 's/.*: *//')
  case $state in
    none) pass "no unfinished update" ;;
    "") info "snapshotctl reported no update state (see snapshotctl.txt)" ;;
    *) warn "update state '$state': reboot and let it finish merging before flashing" ;;
  esac

  say ""
  say "== Root extras"
  mods=$(rsh "ls /data/adb/modules" | tr '\n' ' ')
  info "KernelSU modules: ${mods:-none}"
  if echo "$mods" | grep -qi susfs; then
    warn "a SUSFS module is installed: our build's stock kernel has no SUSFS; remove it before flashing"
  fi
  apex=$(rsh "ls /data/apex/active" | tr '\n' ' ')
  if [ -z "$apex" ]; then pass "no updated APEXes in /data"
  else info "updated APEXes in /data (checked against our re-signed APEXes at boot): $apex"; fi
fi

say ""
say "Result: $fails FAIL, $warns WARN.  Report: $report"
[ "$fails" -eq 0 ]
