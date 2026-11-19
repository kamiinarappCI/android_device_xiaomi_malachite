#!/usr/bin/env bash
# One-off (2026-10-30): retire LineageOS 23.2 in the malachite-project ROM forks.
# Backups of every branch deleted here are git bundles in
# E:\Android\Malachite\branch-backups-20261030 (restore: git fetch <bundle> <ref>).
#
#   bash tools/drop_lineage23_branches.sh          # dry run: prints what it would do
#   bash tools/drop_lineage23_branches.sh --apply  # does it
#
# Kernel-source repos (kernel_device_modules, kernel_xiaomi_mt6878,
# vendor_mediatek_kernel_modules, kernel-build-bazel_mgk_rules, kernel_manifest-6.1)
# only have a branch named lineage-23.2; deleting it would empty them, so they
# are left alone, as is the TWRP tree (A16).
set -uo pipefail
O=malachite-project
run() { if [[ ${1:-} == --apply ]]; then shift; echo "+ $*"; "$@" || echo "  FAILED"; else shift; echo "would: $*"; fi; }
A=${1:-dry}

FORKS="android_device_mediatek_sepolicy_vndr android_device_xiaomi_malachite
android_device_xiaomi_malachite-kernel android_external_wpa_supplicant_8 android_frameworks_base
android_frameworks_native android_hardware_dolby android_hardware_mediatek android_hardware_xiaomi
android_packages_apps_ParanoidSense android_packages_apps_Settings android_packages_modules_Bluetooth
android_packages_services_Telephony android_vendor_mediatek_ims proprietary_vendor_xiaomi_malachite"

# 1. Outside PRs (ridhzlabs crDroid/EvoX/RisingOS ports) would close with lineage-23.2;
#    move them to lineage-24.0 instead (device lineage-24.0 grew from 23.2, same diff).
for n in 21 8 1; do
  run "$A" gh api -X PATCH "repos/$O/android_device_xiaomi_malachite/pulls/$n" -f base=lineage-24.0 --jq '"#\(.number) base=\(.base.ref)"'
done

# 2. lineage-24.0 becomes the default branch.
for r in $FORKS; do
  run "$A" gh api -X PATCH "repos/$O/$r" -f default_branch=lineage-24.0 --jq '"\(.name) default=\(.default_branch)"'
done

# 3. Delete lineage-23.2 in every ROM fork.
for r in $FORKS; do
  run "$A" gh api -X DELETE "repos/$O/$r/git/refs/heads/lineage-23.2"
done

# 4. Delete the 23.2 feature/test branches and the superseded ones.
del() { run "$A" gh api -X DELETE "repos/$O/$1/git/refs/heads/$2"; }
for b in claude/blissful-maxwell-4t52v0 battery-saver-cpu-caps test/20261027-23.2 feature/miface \
         feature/battery-saver-cpu-cap fix/fod-biometric-prompt feature/source-id-23.2; do
  del android_device_xiaomi_malachite "$b"
done
del android_packages_apps_Settings feature/miface
del android_packages_apps_Settings feature/battery-saver-cpu-cap
del android_hardware_xiaomi fix/fod-biometric-prompt
del proprietary_vendor_xiaomi_malachite feature/miface
