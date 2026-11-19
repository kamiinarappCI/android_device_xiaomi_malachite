#!/bin/bash
# Builds malachite-offmode-fix-20261009.zip and malachite-offmode-fix-remove-20261009.zip
# from the 23.2-20261009 release (run in WSL). Every step is checked; see
# notes/2026-10-09-offmode-kernel-findings.md for why.
set -euo pipefail

SRC=/mnt/e/LineageOS-23.2-Malachite/recovery-zip/malachite-offmode-fix
OUT=/mnt/e/LineageOS-23.2-Malachite/recovery-zip
TF=$HOME/android/releases/20261009-release/signed-target_files.zip
L=$HOME/android/lineage
H=$L/out/host/linux-x86/bin
W=$HOME/android/scratch/offmode-zip/make
ORIG_VB=06e1f6477e4e56e209b0b1a753c069a6c566f98089bccf423ff931dd62574986
ORIG_POL=75a11da44c802486bc6f65640aa48a730f0f684c5c07a42ba3cd1735eb3fb070
SALT=05d9d88453ddf74c1d28cbd4bf2b46411edb81e8753952beae5c425a8d09fe8a
FP=Redmi/lineage_malachite/malachite:16/BP4A.251205.006/eng.noamtu:userdebug/release-keys

rm -rf "$W"; mkdir -p "$W"; cd "$W"
unzip -q "$TF" IMAGES/vendor_boot.img 'SYSTEM/etc/selinux/*' 'SYSTEM_EXT/etc/selinux/*' \
  'PRODUCT/etc/selinux/*' 'VENDOR/etc/selinux/*' 'ODM/etc/selinux/*'
[ "$(sha256sum < IMAGES/vendor_boot.img | cut -d' ' -f1)" = "$ORIG_VB" ]
[ "$(head -n1 PRODUCT/etc/selinux/product_sepolicy_and_mapping.sha256)" = "$ORIG_POL" ]

# --- vendor_boot: patch set_charger_partition_info_1 in mtk_charger_framework.ko ---
mkdir -p vb chk
python3 "$L/system/tools/mkbootimg/unpack_bootimg.py" --boot_img IMAGES/vendor_boot.img \
  --out vb --format=mkbootimg > vb/args.txt
"$H/lz4" -d -c vb/vendor_ramdisk00 > rd00.cpio
"$H/lz4" -l -12 --favor-decSpeed -c rd00.cpio | cmp - vb/vendor_ramdisk00   # recompression is exact
python3 - <<'PY'
import struct
d = bytearray(open('rd00.cpio', 'rb').read())
o = 0
while True:
    h = d[o:o + 110]; assert h[:6] == b'070701'
    fs, ns = int(h[54:62], 16), int(h[94:102], 16)
    name = d[o + 110:o + 110 + ns - 1].decode(); do = (o + 110 + ns + 3) & ~3
    if name == 'lib/modules/mtk_charger_framework.ko': break
    assert name != 'TRAILER!!!'; o = (do + fs + 3) & ~3
ko = d[do:do + fs]
shoff, = struct.unpack_from('<Q', ko, 0x28); shent, shnum, shstr = struct.unpack_from('<HHH', ko, 0x3a)
S = [struct.unpack_from('<IIQQQQIIQQ', ko, shoff + i * shent) for i in range(shnum)]
nm = lambda off, tab: ko[tab + off:ko.index(b'\0', tab + off)].decode()
names = [nm(s[0], S[shstr][4]) for s in S]
sym = names.index('.symtab'); strtab = S[S[sym][6]][4]
hits = []
for k in range(S[sym][5] // 24):
    n, info, other, shndx, val, size = struct.unpack_from('<IBBHQQ', ko, S[sym][4] + k * 24)
    if nm(n, strtab) == 'set_charger_partition_info_1': hits.append((shndx, val))
assert len(hits) == 1
shndx, val = hits[0]; assert names[shndx] == '.text'
for i in range(shnum):                       # no relocation may touch the two patched words
    if S[i][1] == 4 and S[i][7] == shndx:
        for r in range(S[i][5] // 24):
            ro, = struct.unpack_from('<Q', ko, S[i][4] + r * 24); assert not (val <= ro < val + 8)
fo = do + S[shndx][4] + val
assert d[fo:fo + 8] == bytes.fromhex('3f2303d5ffc300d1')      # paciasp; sub sp, sp, #0x30
d[fo:fo + 8] = bytes.fromhex('e0031f2ac0035fd6')              # mov w0, wzr; ret
open('rd00-patched.cpio', 'wb').write(d)
PY
[ "$(cmp -l rd00.cpio rd00-patched.cpio | wc -l)" = 8 ]
"$H/lz4" -l -12 --favor-decSpeed -c rd00-patched.cpio > vendor_ramdisk00-patched
repack() { # $1 fragment00, $2 output
  args=$(sed "s#vb/vendor_ramdisk00#$1#" vb/args.txt)
  eval python3 "$L/system/tools/mkbootimg/mkbootimg.py" $args --vendor_boot "$2"
  python3 "$L/external/avb/avbtool.py" add_hash_footer --image "$2" --partition_size 67108864 \
    --partition_name vendor_boot --salt $SALT --prop "com.android.build.vendor_boot.fingerprint:$FP"
}
repack vb/vendor_ramdisk00 repro.img
[ "$(sha256sum < repro.img | cut -d' ' -f1)" = "$ORIG_VB" ]     # repack is exact
repack vendor_ramdisk00-patched vendor_boot-fix.img
FIX_VB=$(sha256sum < vendor_boot-fix.img | cut -d' ' -f1)
python3 "$L/system/tools/mkbootimg/unpack_bootimg.py" --boot_img vendor_boot-fix.img --out chk \
  --format=mkbootimg | sed 's#chk/#vb/#g' | cmp - vb/args.txt
for f in dtb bootconfig vendor_ramdisk01; do cmp chk/$f vb/$f; done
"$H/lz4" -d -c chk/vendor_ramdisk00 | cmp - rd00-patched.cpio

# --- product policy: must compile the way init does, and pass neverallow checks ---
V=$(cat VENDOR/etc/selinux/plat_sepolicy_vers.txt)
compile() { # $1 product cil, $2 out, $3 extra flags
  "$H/secilc" SYSTEM/etc/selinux/plat_sepolicy.cil -m -M true -G $3 -c 30 \
    SYSTEM/etc/selinux/mapping/$V.cil -o "$2" -f /dev/null \
    $(ls SYSTEM/etc/selinux/mapping/$V.compat.cil SYSTEM_EXT/etc/selinux/system_ext_sepolicy.cil \
         SYSTEM_EXT/etc/selinux/mapping/$V.cil SYSTEM_EXT/etc/selinux/mapping/$V.compat.cil 2>/dev/null) \
    "$1" PRODUCT/etc/selinux/mapping/$V.cil VENDOR/etc/selinux/plat_pub_versioned.cil \
    VENDOR/etc/selinux/vendor_sepolicy.cil ODM/etc/selinux/odm_sepolicy.cil \
    SYSTEM/etc/selinux/plat_sepolicy_genfs_$(cat VENDOR/etc/selinux/genfs_labels_version.txt).cil
}
compile PRODUCT/etc/selinux/product_sepolicy.cil orig.pol -N
cmp orig.pol ODM/etc/selinux/precompiled_sepolicy                  # same as the shipped policy
compile "$SRC/files/product_sepolicy.cil" new.pol -N               # what init runs
compile "$SRC/files/product_sepolicy.cil" new-checked.pol ""        # with neverallow checks
"$H/checkfc" new.pol "$SRC/files/product_file_contexts"
FIX_POL=$(cat "$SRC/files/product_sepolicy.cil" PRODUCT/etc/selinux/mapping/$V.cil | sha256sum | cut -d' ' -f1)

# --- zips ---
for m in install remove; do
  Z=$W/zip-$m; mkdir -p "$Z/META-INF/com/google/android" "$Z/orig"
  sed "s/@FIX_VB@/$FIX_VB/; s/@FIX_POL@/$FIX_POL/" "$SRC/update-binary" > "$Z/META-INF/com/google/android/update-binary"
  echo "#MAGIC" > "$Z/META-INF/com/google/android/updater-script"
  printf %s "$m" > "$Z/mode"
  for f in product_sepolicy.cil product_file_contexts product_sepolicy_and_mapping.sha256; do
    cp "PRODUCT/etc/selinux/$f" "$Z/orig/$f"
  done
  if [ $m = install ]; then
    mkdir -p "$Z/files"
    cp "$SRC/files/malachite_offmode_flag.sh" "$SRC/files/malachite_offmode_flag.rc" \
       "$SRC/files/product_sepolicy.cil" "$SRC/files/product_file_contexts" "$Z/files/"
    echo "$FIX_POL" > "$Z/files/product_sepolicy_and_mapping.sha256"
    cp vendor_boot-fix.img "$Z/vendor_boot.img"
    name=malachite-offmode-fix-20261009.zip
  else
    cp IMAGES/vendor_boot.img "$Z/vendor_boot.img"
    name=malachite-offmode-fix-remove-20261009.zip
  fi
  (cd "$Z" && rm -f "$OUT/$name" && python3 - "$OUT/$name" <<'PY'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk('.'):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)[2:]
            i = zipfile.ZipInfo(p, (2009, 1, 1, 0, 0, 0)); i.compress_type = zipfile.ZIP_DEFLATED
            i.external_attr = (0o755 if 'update-binary' in p else 0o644) << 16
            z.writestr(i, open(p, 'rb').read())
PY
  )
done
echo "FIX_VB=$FIX_VB"
echo "FIX_POL=$FIX_POL"
sha256sum "$OUT"/malachite-offmode-fix-*20261009.zip
