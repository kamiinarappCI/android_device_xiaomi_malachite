#!/system/bin/sh
# Collect on-device evidence for the unverified malachite features:
# HDR / 10-bit, QR scanning, Xiaomi camera modes, Netflix HD (Widevine L1).
#
#   adb push tools/feature_check.sh /data/local/tmp/
#   adb shell sh /data/local/tmp/feature_check.sh            # static checks
#   adb shell sh /data/local/tmp/feature_check.sh netflix    # + 90 s log capture
#   adb pull /data/local/tmp/malachite_feature_check.txt
#
# Read-only apart from clearing logcat in netflix mode. The report contains
# no account data, but it does contain the build fingerprint.
OUT=/data/local/tmp/malachite_feature_check.txt

section() { echo; echo "=== $* ==="; }

if [ "$1" = "netflix" ]; then
  echo "Open Netflix and start playing a title now; logging for 90 seconds."
fi

{
echo "malachite feature check  $(date)"
echo "build: $(getprop ro.build.fingerprint)"
echo "lineage: $(getprop ro.lineage.version)"

section "HDR: display capabilities"
dumpsys display 2>/dev/null | grep -m3 -oE "HdrCapabilities\{[^}]*\}|mSupportedHdrTypes=[^,]*"
dumpsys SurfaceFlinger 2>/dev/null | grep -m5 -iE "hdr|wide color|colorMode"
getprop ro.surface_flinger.has_HDR_display
getprop ro.surface_flinger.has_wide_color_display

section "HDR / 10-bit: decoder profiles (HEVC Main10, VP9 Profile 2, AV1)"
# MediaPlayerService prints each codec with its profile/level pairs.
dumpsys media.player 2>/dev/null | awk '
  /c2\.(mtk|android)\.(hevc|vp9|av1)\.decoder/ { show = 1; n = 0 }
  show { print; if (++n > 25) show = 0 }' | grep -iE "decoder|profile|hdr|10" | head -60

section "10-bit: camera dynamic range support"
dumpsys media.camera 2>/dev/null | grep -iE "Camera ID|DYNAMIC_RANGE_TEN_BIT|availableDynamicRangeProfiles|recommendedTenBit" | head -40

section "QR: Quick Settings scanner component"
cmd overlay lookup android android:string/config_defaultQrCodeComponent 2>&1
pm list packages 2>/dev/null | grep -iE "scanner|lens|aperture|googlequicksearchbox"

section "Camera: app and feature properties"
dumpsys package com.android.camera 2>/dev/null | grep -m2 -E "versionName|versionCode"
for p in persist.sys.miui.camera.version ro.product.camera.livephoto.support \
         persist.sys.miui.camera.quickcamera.supported ro.vendor.afbc.enable \
         ro.vendor.hdr10plus.enable ro.vendor.mtk_hdr_video_support; do
  echo "$p=$(getprop $p)"
done
echo "-- camera crashes since boot:"
logcat -d -b crash 2>/dev/null | grep -iE "camera|mialgo|mivi" | tail -20

section "Netflix / Widevine"
for p in ro.netflix.bsp_rev ro.vendor.mtk_sec_video_path_support drm.service.enabled \
         ro.product.model ro.product.manufacturer; do
  echo "$p=$(getprop $p)"
done
dumpsys package com.netflix.mediaclient 2>/dev/null | grep -m1 versionName || echo "Netflix not installed"
echo "-- secure decoders visible to apps:"
dumpsys media.player 2>/dev/null | grep -oE "c2\.mtk\.[a-z0-9]+\.decoder\.secure" | sort -u
echo "-- Widevine HAL:"
service list 2>/dev/null | grep -iE "drm|widevine"
dumpsys android.hardware.drm.IDrmFactory/widevine 2>/dev/null | head -20

if [ "$1" = "netflix" ]; then
  section "Netflix playback log (90 s)"
  logcat -c
  sleep 90
  logcat -d 2>/dev/null | grep -iE "widevine|wvcdm|drm|MediaCodec.*secure|c2\.mtk.*secure|nf_|netflix|oemcrypto|tee|mitee" | tail -300
fi
} > "$OUT" 2>&1

echo "Wrote $OUT"
