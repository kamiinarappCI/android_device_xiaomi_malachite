#!/system/bin/sh
#
# Find and fix the WPA3 version bit in whatever wpa_supplicant the ROM ships.
#
# The malachite Wi-Fi driver (wlan_drv_gen4m_6878.ko) understands nl80211 WPA
# version bits 0x1 and 0x2 only. Android 16's supplicant sends
# NL80211_WPA_VERSION_3 (0x4) for SAE, so the driver drops the AKM and WPA3
# association fails. In nl80211_connect_common() the compiled code is:
#
#       orr   wR, wR, #4          <- SAE: ver |= NL80211_WPA_VERSION_3
#       b     L
#       ...
#       orr   wR, wR, #2          <- otherwise: ver |= NL80211_WPA_VERSION_2
#   L:  adrp  xS, "  * WPA Versions 0x%x"
#       add   xS, xS, :lo12:...
#
# The fix changes the #4 to #2: one byte (the immr field, 0x1e -> 0x1f). The
# match needs all of the above, including the address of that log string, and
# must be unique, or nothing is patched. A ROM built with the source fix
# (CONFIG_DISABLE_WPA_VERSION_3) has no "orr #4" there and is left alone.
#
# Usage: wpa3.sh scan FILE        prints "patch OFF", "patched OFF" or "none"
#        wpa3.sh refresh MODDIR   checks the ROM and updates the module files

ANCHOR='  * WPA Versions 0x%x'
TARGET=${WPA3_FIX_TARGET:-/vendor/bin/hw/wpa_supplicant}
VCONF=${WPA3_FIX_VCONF:-/vendor/etc/wifi/wpa_supplicant.conf}
DRIVERS=${WPA3_FIX_DRIVER:-/vendor_dlkm/lib/modules/wlan_drv_gen4m_6878.ko /vendor/lib/modules/wlan_drv_gen4m_6878.ko}
BIN_CTX=u:object_r:hal_wifi_supplicant_default_exec:s0
CONF_CTX=u:object_r:vendor_configs_file:s0

sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
prop() { getprop "$1" 2>/dev/null; }

# Candidates as "kind instruction_offset string_offset", from the ELF's own
# program headers (file offset <-> address). Arithmetic only, no bitwise
# functions, so any awk works.
candidates() {
  od -An -v -tu4 "$1" | awk '
    { for (k = 1; k <= NF; k++) w[n++] = $k + 0 }
    function bits(x, lo, len) { return int(x / 2 ^ lo) % 2 ^ len }
    function sext(v, len) { return v >= 2 ^ (len - 1) ? v - 2 ^ len : v }
    # orr wR, wR, #imm (32-bit, Rd == Rn): immr 30 is #4, 31 is #2
    function orr(x, immr) {
      return int(x / 2 ^ 22) == 200 && bits(x, 16, 6) == immr && bits(x, 10, 6) == 0 &&
             bits(x, 0, 5) == bits(x, 5, 5)
    }
    function o2v(o,  j) { for (j = 0; j < nl; j++) if (o >= po[j] && o < po[j] + pf[j]) return o - po[j] + pv[j]; return -1 }
    function v2o(v,  j) { for (j = 0; j < nl; j++) if (v >= pv[j] && v < pv[j] + pf[j]) return v - pv[j] + po[j]; return -1 }
    END {
      # 64-bit little-endian AArch64 ELF: "\177ELF", class 2, machine 183
      if (w[0] != 1179403647 || bits(w[1], 0, 8) != 2 || bits(w[4], 16, 16) != 183) exit
      phoff = w[8] + w[9] * 2 ^ 32; phent = bits(w[13], 16, 16); phnum = bits(w[14], 0, 16)
      nl = 0
      for (i = 0; i < phnum; i++) {
        b = (phoff + i * phent) / 4
        if (w[b] == 1) { po[nl] = w[b + 2] + w[b + 3] * 2 ^ 32; pv[nl] = w[b + 4] + w[b + 5] * 2 ^ 32
                         pf[nl] = w[b + 8] + w[b + 9] * 2 ^ 32; nl++ }
      }
      for (i = 0; i + 1 < n; i++) {
        x = w[i]
        if (orr(x, 30)) kind = "patch"; else if (orr(x, 31)) kind = "patched"; else continue
        br = w[i + 1]
        if (int(br / 2 ^ 26) != 5) continue                  # b <label>
        t = i + 1 + sext(bits(br, 0, 26), 26)                # label, in words
        if (t < 1 || t + 1 >= n || !orr(w[t - 1], 31) || bits(w[t - 1], 0, 5) != bits(x, 0, 5)) continue
        ad = w[t]; ai = w[t + 1]
        if (int(ad / 2 ^ 31) != 1 || bits(ad, 24, 5) != 16) continue      # adrp
        if (int(ai / 2 ^ 23) != 290 || bits(ai, 5, 5) != bits(ad, 0, 5)) continue  # add xS, xS, #imm
        pc = o2v(t * 4); if (pc < 0) continue
        page = pc - pc % 4096 + sext(bits(ad, 5, 19) * 4 + bits(ad, 29, 2), 21) * 4096
        addr = page + bits(ai, 10, 12) * (bits(ai, 22, 1) ? 4096 : 1)
        so = v2o(addr); if (so < 0) continue
        printf "%s %d %d\n", kind, i * 4, so
      }
    }'
}

scan() {
  found=$(candidates "$1" | while read -r kind off so; do
    s=$(dd if="$1" bs=1 skip="$so" count=${#ANCHOR} 2>/dev/null)
    [ "$s" = "$ANCHOR" ] && echo "$kind $off"
  done)
  np=$(echo "$found" | grep -c '^patch ')
  nd=$(echo "$found" | grep -c '^patched ')
  if [ "$np" -eq 1 ] && [ "$nd" -eq 0 ]; then echo "$found"
  elif [ "$np" -eq 0 ] && [ "$nd" -eq 1 ]; then echo "$found"
  else echo "none"; fi
}

# setbyte FILE OFFSET OCTAL
setbyte() { printf "\\$3" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null; }

refresh() {
  M=$1
  BIN=$M/system/vendor/bin/hw/wpa_supplicant
  OV=$M/system/vendor/etc/wifi/wpa_supplicant.conf

  status() {
    echo "$1"
    [ -f "$M/module.prop" ] || return 0
    sed "s|^description=.*|description=WPA3 fix for malachite. Status: $1. Remove the module to restore pmf.|" "$M/module.prop" > "$M/module.prop.tmp" &&
      cat "$M/module.prop.tmp" > "$M/module.prop"; rm -f "$M/module.prop.tmp"
  }
  drop_bin() { rm -f "$BIN"; rmdir "$M/system/vendor/bin/hw" "$M/system/vendor/bin" 2>/dev/null; }
  install_bin() { # SOURCE  (already patched)
    mkdir -p "${BIN%/*}" && cp "$1" "$BIN.tmp" && mv "$BIN.tmp" "$BIN" || return 1
    chown 0:0 "$BIN" 2>/dev/null; chmod 0755 "$BIN"
    chcon "$(ctx "$TARGET" "$BIN_CTX")" "$BIN" 2>/dev/null
    return 0
  }

  dev=${WPA3_FIX_DEVICE:-$(prop ro.product.device)}
  if [ "$dev" != malachite ]; then
    drop_bin; rm -f "$OV"; status "inactive: this is $dev, not malachite"; return 0
  fi

  # --- pmf=1 in the vendor template (the live copy is pmf.sh's job) --------
  if [ -f "$VCONF" ]; then
    if [ -f "$OV" ] && cmp -s "$VCONF" "$OV"; then
      :   # our overlay is what /vendor shows right now; keep it
    elif grep -q '^pmf=1$' "$VCONF"; then
      rm -f "$OV"
    else
      mkdir -p "${OV%/*}"
      if grep -q '^pmf=' "$VCONF"; then sed 's/^pmf=.*/pmf=1/' "$VCONF" > "$OV.tmp"
      else { cat "$VCONF"; echo; echo "pmf=1"; } > "$OV.tmp"; fi
      mv "$OV.tmp" "$OV"; chmod 0644 "$OV"; chown 0:0 "$OV" 2>/dev/null
      chcon "$(ctx "$VCONF" "$CONF_CTX")" "$OV" 2>/dev/null
    fi
  fi

  # --- the version bit --------------------------------------------------------
  # Only the MediaTek gen4m 6878 driver rejects version 3; with any other
  # driver the ROM's supplicant is right as it is.
  drv=
  for d in $DRIVERS; do [ -f "$d" ] && drv=$d && break; done
  if [ -z "$drv" ]; then
    drop_bin; rm -f "$M/stock_sha" "$M/patched_sha"
    status "wlan_drv_gen4m_6878 driver not found; wpa_supplicant not modified"; return 0
  fi
  if [ ! -f "$TARGET" ]; then
    drop_bin; status "no wpa_supplicant at $TARGET; nothing patched"; return 0
  fi
  cur=$(sha "$TARGET")
  fp=${WPA3_FIX_FP:-$(prop ro.vendor.build.fingerprint)}
  if [ -f "$BIN" ] && [ "$cur" = "$(cat "$M/patched_sha" 2>/dev/null)" ]; then
    # /vendor already shows our copy, so the ROM's own file is hidden. Same
    # vendor build: nothing changed. New vendor build: drop the copy so the
    # next boot sees the ROM's file and checks it.
    if [ "$fp" = "$(cat "$M/vendor_fp" 2>/dev/null)" ]; then return 0; fi
    drop_bin; rm -f "$M/stock_sha" "$M/patched_sha"
    status "ROM changed; the patch is off until the next boot re-checks"
    return 0
  fi
  if [ "$cur" = "$(cat "$M/stock_sha" 2>/dev/null)" ] && { [ -f "$BIN" ] || [ ! -f "$M/patched_sha" ]; }; then
    echo "$fp" > "$M/vendor_fp"   # same file under a new build: still valid
    return 0
  fi

  echo "$fp" > "$M/vendor_fp"
  set -- $(scan "$TARGET")
  tmp=$M/.wpa_supplicant.tmp
  case $1 in
    patch)
      cp "$TARGET" "$tmp" && setbyte "$tmp" $(($2 + 2)) 037
      if [ "$(scan "$tmp")" = "patched $2" ] && [ "$(cmp -l "$TARGET" "$tmp" | wc -l)" -eq 1 ] && install_bin "$tmp"; then
        echo "$cur" > "$M/stock_sha"; sha "$BIN" > "$M/patched_sha"
        status "active, version bit patched at offset $2"
      else
        drop_bin; rm -f "$M/patched_sha"; echo "$cur" > "$M/stock_sha"
        status "patch did not verify; wpa_supplicant left unmodified"
      fi
      ;;
    patched)
      # Already has #2 in the SAE branch: an earlier version of this module
      # mounted over /vendor, or a ROM patched the same way. Keep serving it
      # and remember the ROM file it came from.
      cp "$TARGET" "$tmp" && setbyte "$tmp" $(($2 + 2)) 036
      install_bin "$TARGET" && echo "$(sha "$tmp")" > "$M/stock_sha" && echo "$cur" > "$M/patched_sha"
      status "active, version bit patched at offset $2"
      ;;
    *)
      drop_bin; rm -f "$M/patched_sha"; echo "$cur" > "$M/stock_sha"
      status "wpa_supplicant not modified: its WPA3 version code was not found (already fixed, or a build this module does not recognise)"
      ;;
  esac
  rm -f "$tmp"
  return 0
}

# SELinux label of FILE, or DEFAULT if it cannot be read.
ctx() {
  c=$(ls -Z "$1" 2>/dev/null | awk '{print $1}')
  case $c in u:object_r:*) echo "$c" ;; *) echo "$2" ;; esac
}

case $1 in
  scan) scan "$2" ;;
  refresh) refresh "$2" ;;
  *) echo "usage: $0 scan FILE | refresh MODDIR" >&2; exit 2 ;;
esac
