#!/usr/bin/env bash
# Make the root filesystem of "MalachiteBuild", a tiny WSL distribution whose
# only job is to hold the build tree's source checkout and out/ on the C: SSD
# (its disk file is C:\WSL\MalachiteBuild\ext4.vhdx). Ubuntu keeps everything
# else, including the git history (.repo), on E:.
#
#   wsl -u root bash /mnt/e/LineageOS-23.2-Malachite/tools/make_build_disk_rootfs.sh <out.tar> [user]
#
# Run as root (file owners must be set); <user> (default noamtu123) owns /build.
#
# Then, from Windows:  wsl --import MalachiteBuild C:\WSL\MalachiteBuild <out.tar> --version 2
#
# Why a distribution and not `wsl --mount --vhd`: mounting a disk into WSL needs
# administrator rights on every start; importing and starting a distribution
# does not. At start, MalachiteBuild bind-mounts its /build into /mnt/wsl (replacing
# a stale mount left by an earlier instance), which
# all WSL 2 distributions share, and build_disk.sh mounts that over
# ~/android/lineage in Ubuntu, so every path stays the same.
set -euo pipefail
OUT=$1
U=${2:-noamtu123}
UID_=$(id -u "$U"); GID_=$(id -g "$U"); GNAME=$(id -gn "$U")
[ "$(id -u)" = 0 ] || { echo "run as root (wsl -u root)"; exit 1; }
R=$(mktemp -d)
trap 'rm -rf "$R"' EXIT

bins="/bin/sh /bin/mount /bin/umount /bin/mkdir /bin/sleep /bin/mountpoint /bin/ls /bin/cat /bin/df /bin/chown /bin/date /bin/stat /bin/touch /bin/sort /bin/tail"
mkdir -p "$R"/{bin,etc,lib,lib64,usr,build,proc,sys,dev,tmp,root,mnt/wsl}
for b in $bins; do
  real=$(readlink -f "$b")
  cp -L "$real" "$R/bin/$(basename "$b")"
  for lib in $(ldd "$real" | grep -oE '/[^ ]+\.so[^ ]*'); do
    mkdir -p "$R$(dirname "$lib")"
    cp -L "$lib" "$R$lib"
  done
done
chmod 1777 "$R/tmp"
# The build tree belongs to the same user as in Ubuntu (numeric ids match).
chown "$UID_:$GID_" "$R/build"

cat > "$R/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/sh
$U:x:$UID_:$GID_::/build:/bin/sh
EOF
cat > "$R/etc/group" <<EOF
root:x:0:
$GNAME:x:$GID_:
EOF
cat > "$R/etc/wsl.conf" <<'EOF'
[boot]
command = /bin/umount -l /mnt/wsl/malachite-build 2>/dev/null; /bin/mkdir -p /mnt/wsl/malachite-build && /bin/mount --bind /build /mnt/wsl/malachite-build

[automount]
enabled = false

[interop]
enabled = false
appendWindowsPath = false

[user]
default = root
EOF
tar -C "$R" --numeric-owner -cf "$OUT" .
echo "rootfs: $OUT ($(du -h "$OUT" | cut -f1))"
