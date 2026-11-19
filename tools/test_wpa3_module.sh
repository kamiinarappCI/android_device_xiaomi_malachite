#!/bin/sh
# Exercise ksu-module/malachite-wpa3-fix/wpa3.sh against scratch files.
# Needs a stock malachite wpa_supplicant (not in git):
#
#   sh tools/test_wpa3_module.sh [stock wpa_supplicant]
#
# Without an argument it rebuilds the stock file from the v1.x patched copy
# (ksu-module/wpa_supplicant.patched) and checks its hash. Run on Linux; the
# phone runs the same script under busybox.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/ksu-module/malachite-wpa3-fix
STOCK_SHA=d8e3d8c5774c843c0c1c5a60afa4d0c91253c8bb154de440da9245e040da1dbc
V1_PATCHED_SHA=74386491ceb9bc6abecdf03d8c8e2a3f38989b8d0c5c8369d970d11f8d296324
SITE=1154044   # 0x119bfc in that build
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1  (want [$3] got [$2])"; fi; }
sha() { sha256sum "$1" | awk '{print $1}'; }

W=$(mktemp -d)
if [ $# -ge 1 ]; then
  cp "$1" "$W/stock"
else
  cp "$ROOT/ksu-module/wpa_supplicant.patched" "$W/stock" || { echo "no stock binary"; exit 2; }
  printf '\036' | dd of="$W/stock" bs=1 seek=$((SITE + 2)) conv=notrunc 2>/dev/null
fi
check "stock binary is the analysed build"  "$(sha "$W/stock")" "$STOCK_SHA"

# --- scan ---------------------------------------------------------------------
check "scan finds the SAE site"             "$(sh "$SRC/wpa3.sh" scan "$W/stock")" "patch $SITE"
cp "$W/stock" "$W/nop"; printf '\037\040\003\325' | dd of="$W/nop" bs=1 seek=$SITE conv=notrunc 2>/dev/null
check "no orr #4 (source-fixed ROM): none"  "$(sh "$SRC/wpa3.sh" scan "$W/nop")" "none"
check "unrelated binary: none"              "$(sh "$SRC/wpa3.sh" scan /bin/sh)" "none"

# --- refresh --------------------------------------------------------------------
# new_module: a fresh module dir; rom <supplicant> <template pmf line>
new_module() { rm -rf "$W/m"; mkdir "$W/m"; cp "$SRC/module.prop" "$W/m/"; }
rom() { cp "$1" "$W/vendor_bin"; printf 'ctrl_interface=wlan0\n%s\n' "$2" > "$W/vendor_conf"; }
touch "$W/driver"
refresh() {
  WPA3_FIX_DRIVER=${DRV:-$W/driver} \
  WPA3_FIX_TARGET="$W/vendor_bin" WPA3_FIX_VCONF="$W/vendor_conf" WPA3_FIX_DEVICE=${DEV:-malachite} \
    WPA3_FIX_FP=${FP:-build/A} sh "$SRC/wpa3.sh" refresh "$W/m"
}
BIN=system/vendor/bin/hw/wpa_supplicant
OVC=system/vendor/etc/wifi/wpa_supplicant.conf
has() { [ -e "$W/m/$1" ] && echo yes || echo no; }
desc() { sed -n 's/^description=WPA3 fix for malachite. Status: //p' "$W/m/module.prop" | cut -c1-24; }

new_module; rom "$W/stock" "pmf=0"; refresh > /dev/null
check "install: patched copy built"         "$(sha "$W/m/$BIN")" "$V1_PATCHED_SHA"
check "install: one byte differs"           "$(cmp -l "$W/stock" "$W/m/$BIN" | wc -l)" "1"
check "install: status shown"               "$(desc)" "active, version bit patc"
check "install: template overlay has pmf=1" "$(grep '^pmf=' "$W/m/$OVC")" "pmf=1"
check "install: template otherwise same"    "$(grep -c ctrl_interface "$W/m/$OVC")" "1"

touch -d '2000-01-01' "$W/m/$BIN"; refresh > /dev/null
check "reboot, same ROM: copy untouched"    "$(date -r "$W/m/$BIN" +%Y)" "2000"

rom "$W/m/$BIN" "pmf=1"; cp "$W/m/$OVC" "$W/vendor_conf"; refresh > /dev/null
check "overlay visible, same ROM: kept"     "$(has $BIN)/$(has $OVC)" "yes/yes"

FP=build/B refresh > /dev/null
check "overlay visible, new ROM: dropped"   "$(has $BIN)" "no"
check "overlay visible, new ROM: status"    "$(desc)" "ROM changed; the patch i"

rom "$W/stock" "pmf=0"; FP=build/B refresh > /dev/null
check "next boot sees the ROM file: patched" "$(sha "$W/m/$BIN")" "$V1_PATCHED_SHA"

rom "$W/nop" "pmf=1"; echo "sae_pwe=2" >> "$W/vendor_conf"; FP=build/C refresh > /dev/null
check "fixed ROM: copy dropped"             "$(has $BIN)" "no"
check "fixed ROM: template overlay dropped" "$(has $OVC)" "no"
check "fixed ROM: status"                   "$(desc)" "wpa_supplicant not modif"
FP=build/C refresh > /dev/null
check "fixed ROM, reboot: stays off"        "$(has $BIN)" "no"

# Upgrade from v1.x: KernelSU still shows the old patched copy at install.
new_module; rom "$W/m/../stock" "pmf=0"; cp "$SRC/../wpa_supplicant.patched" "$W/vendor_bin" 2>/dev/null ||
  { cp "$W/stock" "$W/vendor_bin"; printf '\037' | dd of="$W/vendor_bin" bs=1 seek=$((SITE + 2)) conv=notrunc 2>/dev/null; }
refresh > /dev/null
check "upgrade from v1: serves the patch"   "$(sha "$W/m/$BIN")" "$V1_PATCHED_SHA"
check "upgrade from v1: knows the stock"    "$(cat "$W/m/stock_sha")" "$STOCK_SHA"

new_module; rom "$W/stock" "pmf=0"; DEV=garnet refresh > /dev/null
check "other device: nothing installed"     "$(has $BIN)/$(has $OVC)" "no/no"

new_module; rm -f "$W/vendor_bin"; refresh > /dev/null
check "no supplicant: nothing installed"    "$(has $BIN)" "no"

new_module; rom "$W/stock" "pmf=0"; DRV="$W/none /also/none" refresh > /dev/null
check "no gen4m driver: supplicant left"    "$(has $BIN)" "no"
check "no gen4m driver: status"             "$(desc)" "wlan_drv_gen4m_6878 driv"
new_module; rom "$W/stock" "pmf=0"; DRV="$W/none $W/driver" refresh > /dev/null
check "driver in second location: patched"  "$(has $BIN)" "yes"
new_module; rom "$W/stock" "pmf=0"; refresh > /dev/null; DRV="$W/none" refresh > /dev/null
check "driver gone after update: dropped"   "$(has $BIN)" "no"

# --- customize.sh (the installer), with KernelSU's helpers stubbed ------------
install() { # device
  rm -rf "$W/inst"; mkdir -p "$W/inst/mod" "$W/inst/bin"
  cp "$SRC"/*.sh "$SRC/module.prop" "$W/inst/mod/"
  printf '#!/bin/sh\n[ "$1" = ro.product.device ] && echo %s\n' "$1" > "$W/inst/bin/getprop"
  chmod +x "$W/inst/bin/getprop"
  PATH="$W/inst/bin:$PATH" MODPATH="$W/inst/mod" sh -c '
    ui_print() { echo "$*"; }; abort() { echo "$*"; exit 1; }; set_perm() { :; }
    . "$MODPATH/customize.sh"' > "$W/inst/out" 2>&1
  echo $?
}
check "installer: other device aborts"      "$(install garnet)" "1"
check "installer: says why"                 "$(grep -c "targets malachite only" "$W/inst/out")" "1"
check "installer: nothing set up"           "$(ls "$W/inst/mod" | grep -c orig_pmf)" "0"
check "installer: malachite proceeds"       "$(install malachite)" "0"

rm -rf "$W"; echo "wpa3.sh: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
