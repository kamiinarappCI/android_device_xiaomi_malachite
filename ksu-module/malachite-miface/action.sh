#!/system/bin/sh
# Action button: show whether face unlock is running and copy the log, with
# this boot's face/camera log lines and SELinux denials, to
# Download/malachite_miface.txt for sharing.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

pid=$(pidof mifaced)
echo "mifaced: ${pid:+running, pid $pid}${pid:-NOT running}"
echo "IFace/default: $(service check android.hardware.biometrics.face.IFace/default 2>&1 | sed 's/.*: //')"
dumpsys face 2>/dev/null | grep -m4 -iE 'sensor|strength|enrolled'

OUT=/sdcard/Download/malachite_miface.txt
{
  cat "$LOG" 2>/dev/null
  echo
  echo "== dumpsys face"
  dumpsys face 2>/dev/null | head -60
  echo
  echo "== log (miface / FaceService / camera)"
  logcat -d -b all 2>/dev/null | grep -iE 'miface|mifaced|FaceService|FaceProvider|Biometric|ACamera|CameraService.*1000' | tail -400
  echo
  echo "== SELinux denials"
  logcat -d -b all 2>/dev/null | grep 'avc:  denied' | grep -E 'hal_face|cameraserver' | tail -100
} > "$OUT" 2>/dev/null
echo
echo "Log copied to Download/malachite_miface.txt"
