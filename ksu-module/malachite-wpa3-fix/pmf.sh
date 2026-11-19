#!/system/bin/sh
#
# Apply or restore pmf in the supplicant's live configuration.
#
# The supplicant runs from /data/vendor/wifi/wpa/wpa_supplicant.conf. That file
# is copied from /vendor/etc/wifi/wpa_supplicant.conf only when it does not
# already exist, so an overlay of the vendor file never reaches an existing
# install. This script edits the live copy directly.
#
# Usage: pmf.sh apply | restore

MODDIR=${0%/*}
CONF=${PMF_CONF:-/data/vendor/wifi/wpa/wpa_supplicant.conf}
TMP="$MODDIR/.wpa_supplicant.conf.tmp"

[ -f "$CONF" ] || exit 0

# Write back with cat rather than sed -i or mv. Both of those replace the file,
# which would drop its owner, mode and SELinux label; cat keeps the inode.
write_back() {
  cat "$TMP" > "$CONF" && rm -f "$TMP"
}

case "$1" in
  apply)
    grep -q '^pmf=1$' "$CONF" && exit 0
    if grep -q '^pmf=' "$CONF"; then
      sed 's/^pmf=.*/pmf=1/' "$CONF" > "$TMP" && write_back
    else
      { cat "$CONF"; echo; echo "pmf=1"; } > "$TMP" && write_back
    fi
    ;;
  restore)
    ORIG=$(cat "$MODDIR/orig_pmf" 2>/dev/null)
    case "$ORIG" in
      pmf=*) sed "s/^pmf=.*/$ORIG/" "$CONF" > "$TMP" && write_back ;;
      none)  sed '/^pmf=/d' "$CONF" > "$TMP" && write_back ;;
    esac
    ;;
esac
