# Shared by the module's scripts.
LOG=${MIFACE_LOG:-/data/local/tmp/malachite_miface.log}
HAL=/vendor/bin/hw/mifaced
FACE_DATA=/data/vendor/face
BB=/data/adb/ksu/bin/busybox
SENSE_PKG=co.aospa.sense
# ParanoidSense's overlays; also disabled at runtime, in case this root setup
# does not apply the whiteouts from REMOVE in customize.sh.
SENSE_OVERLAYS="co.aospa.sense.settings.overlay co.aospa.sense.auto_generated_rro_product__"

log() { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }

# Re-read the VINTF manifests: libvintf (servicemanager) caches them until
# the APEX info list changes, and may have read them before this module's
# miface.xml was mounted. Touching the list costs one re-read.
refresh_vintf() {
  for f in /apex/apex-info-list.xml /bootstrap-apex/apex-info-list.xml; do
    [ -e "$f" ] && touch -c "$f" 2>/dev/null
  done
}
