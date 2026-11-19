#!/system/bin/sh
# Read-only check before dirty-flashing a build signed with our keys over
# chara's release. No root needed.
#
#   adb push tools/signer_inventory.sh /data/local/tmp/
#   adb shell sh /data/local/tmp/signer_inventory.sh
#   adb pull /data/local/tmp/malachite_signers.txt
#
# What breaks on a key change, in LineageOS 23.2's package manager
# (ReconcilePackageUtils): a preinstalled app whose signature changed keeps its
# data. Two things do not survive:
#   1. An app installed in /data (a user app, or an update of a system app)
#      signed with one of the ROM's own keys: its code is dropped at boot.
#   2. A shared UID whose preinstalled members end up with different signers:
#      system_server throws and the phone bootloops.
# This lists both, from what the phone has installed now. The report has
# package names and certificate digests only.
OUT=/data/local/tmp/malachite_signers.txt
TMP=/data/local/tmp/malachite_signers.$$

dumpsys package packages > "$TMP" 2>/dev/null

{
echo "malachite signer inventory  $(date)"
echo "build: $(getprop ro.build.fingerprint)"
echo "tags: $(getprop ro.build.tags)  type: $(getprop ro.build.type)"
echo

awk '
  # Stop before the disabled copies of updated system apps.
  /^Hidden system packages:/ { exit }
  /^  Package \[/ {
    name = $2; gsub(/[\[\]]/, "", name)
    order[++n] = name
    next
  }
  name == "" { next }
  /^    sharedUser=/ {
    s = $0; sub(/.* /, "", s); sub(/\/.*/, "", s); shared[name] = s
  }
  /^    codePath=/ { s = $0; sub(/.*codePath=/, "", s); path[name] = s }
  /^    signatures=PackageSignatures/ {
    # The current signers, not "past signatures:[...]".
    if (match($0, /, signatures:\[[^]]*\]/)) {
      s = substr($0, RSTART + 14, RLENGTH - 15); gsub(/ /, "", s)
      signer[name] = s
    }
  }
  /^    pkgFlags=/ { flags[name] = $0 }
  END {
    # The ROM keys: platform (android), media (DownloadProvider),
    # shared (ContactsProvider). Everything preinstalled and signed by one of
    # these is re-signed by our build.
    rom[signer["android"]] = "platform"
    if (signer["com.android.providers.downloads"] != "")
      rom[signer["com.android.providers.downloads"]] = "media"
    if (signer["com.android.providers.contacts"] != "")
      rom[signer["com.android.providers.contacts"]] = "shared"
    # Keys that sign an app under /system, /system_ext, /product, /vendor or
    # /odm but not the three above: releasekey or a PRESIGNED vendor key.
    for (i = 1; i <= n; i++) {
      p = order[i]
      if (path[p] !~ /^\/data\// && !(signer[p] in rom)) other[signer[p]]++
    }

    print "== ROM keys"
    for (k in rom) print "  " rom[k] ": " k
    print ""
    print "== Other keys on the system partitions (releasekey is one of them;"
    print "   PRESIGNED Google/Xiaomi keys do not change). Preinstalled apps per key:"
    for (k in other) print "  " k ": " other[k]
    print ""

    print "== 1. Apps in /data signed with a ROM key (lose their code on a key change)"
    bad = 0
    for (i = 1; i <= n; i++) {
      p = order[i]
      if (path[p] ~ /^\/data\// && (signer[p] in rom)) {
        print "  " p "  [" rom[signer[p]] "]  " path[p]
        bad++
      }
    }
    if (!bad) print "  none"
    print ""
    print "== 1b. Apps in /data signed with another system-partition key"
    print "   (a problem only if that key is releasekey, not a PRESIGNED one)"
    bad = 0
    for (i = 1; i <= n; i++) {
      p = order[i]
      if (path[p] ~ /^\/data\// && (signer[p] in other)) {
        print "  " p "  " signer[p] "  " path[p]
        bad++
      }
    }
    if (!bad) print "  none"
    print ""

    print "== 2. Shared UIDs: members and signers (one signer per UID is required)"
    for (i = 1; i <= n; i++) {
      p = order[i]
      if (shared[p] == "") continue
      u = shared[p]
      members[u] = members[u] "    " p "  " signer[p] "  " path[p] "\n"
      if (!((u, signer[p]) in seen)) { seen[u, signer[p]] = 1; signers[u]++ }
      uids[u] = 1
    }
    for (u in uids) {
      print "  " u (signers[u] > 1 ? "   <-- MIXED SIGNERS" : "")
      printf "%s", members[u]
    }
  }
' "$TMP"
} > "$OUT"
rm -f "$TMP"
echo "Wrote $OUT"
