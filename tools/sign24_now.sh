#!/bin/bash
# Sign and package the server-built 24.0 target-files (tools already built in the 24.0 tree).
bash /mnt/e/LineageOS-23.2-Malachite/tools/build_disk.sh up >/dev/null
T=/mnt/wsl/malachite-build/lineage-24
W=$HOME/android/server-20261027-24.0
cd "$T" || exit 1
export PATH=$T/out/host/linux-x86/bin:$HOME/android/hosttools-24.0/linux-x86/bin:$PATH
export MALACHITE_STATE=/mnt/e/Android/Malachite/builds/server-20261027-24.0/tree-state.txt MALACHITE_VER=24.0
bash /mnt/e/LineageOS-23.2-Malachite/tools/sign_build.sh "$W/lineage_malachite-target_files.zip" > "$HOME/android/sign24-direct.log" 2>&1
echo "exit=$?" >> "$HOME/android/sign24-direct.log"
