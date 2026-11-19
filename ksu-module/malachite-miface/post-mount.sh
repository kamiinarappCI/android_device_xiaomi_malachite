#!/system/bin/sh
# Runs once KernelSU has mounted system/, still before zygote: make
# servicemanager see miface.xml before system_server asks which face HALs
# are declared.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

refresh_vintf
