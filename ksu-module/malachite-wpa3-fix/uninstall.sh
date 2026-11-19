#!/system/bin/sh
# Put the supplicant's pmf value back to what it was before this module.
MODDIR=${0%/*}
sh "$MODDIR/pmf.sh" restore
