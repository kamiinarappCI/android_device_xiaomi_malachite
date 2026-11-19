# malachite workspace

Fixes and builds of unofficial LineageOS 24.0, crDroid 13.0 and Evolution X 12.3
(all Android 17) for the Redmi Note 14 Pro 5G / POCO X7 (`malachite`, MediaTek
MT6878), independent of the original maintainers: every repository a build needs is
forked into the [`malachite-project`](https://github.com/malachite-project) organization.

This repository holds the notes, tools and KernelSU modules. It is kept local (no
remote); the source changes live in the forks. The folder name is historical (the
work started on LineageOS 23.2).

Baseline: cmdr-chara's 11 September 2026 release (device tree `lineage-23.2` at
`a3c7b5b`), stock firmware `OS2.0.208.0.VOOMIXM`. **For the full current state read
`HANDOFF.md` first.**

## Current state (2026-10-31)

| Release | Folder (`E:\Android\Malachite\builds`) | Notes |
| --- | --- | --- |
| LineageOS 24.0 | `20261031-24.0-release-test` | changelog `changelog-lineage-24.0-20261031.txt` |
| Evolution X 12.3, Google apps | `EvolutionX-cnb-20261031-gapps-test` | `notes/2026-10-29-evolutionx-port.md` |
| crDroid 13.0 | `crDroid-17.0-20261031-test` | `notes/2026-10-29-crdroid17-port.md` |

All three: build ID `CP2A.260605.016`, release-key signed, built on a ServerHive rental.
Tester-confirmed on 24.0: camera, FOD, DT2W, Wi-Fi, boot speed. Open items and what still
needs a phone: `HANDOFF.md` section 8, `notes/2026-10-31-los24-tester-report.md`.

The last Android 16 release was LineageOS 23.2 `20261016-5`; `lineage-23.2` is retired.

## Layout

| Path | Contents |
| --- | --- |
| `notes/` | Findings, one file per topic and date (index below) |
| `tools/` | Build, signing, phone checks, simulators (index below) |
| `ksu-module/` | KernelSU modules for chara's release (index below) |
| `patches/` | `frameworks_base-0001-migration-reset-package-signatures.patch`, from the key-migration plan; not used (`notes/2026-09-22-key-migration.md`) |
| `evidence/` | Bug reports and phone captures — **gitignored**, they contain identifiers |
| `src/` | Windows reference checkouts of the forks and research clones — **gitignored** |

The build trees are in WSL (`/mnt/wsl/malachite-build/lineage-24` for 24.0, the frozen
23.2 tree at `~/android/lineage`); `src/` is for reading. In each fork checkout `origin` is the fork and any
`upstream` has its push URL disabled, so a stray `git push` cannot reach
cmdr-chara or LineageOS.

## Forks

`lineage-24.0` is every fork's default branch and the main line. `crdroid-17.0` and
`evolutionx-24.0` are the crDroid and Evolution X ports, kept level with it: the device,
vendor and hardware forks merge `lineage-24.0` in; the framework forks (base, native,
Settings, Telephony, Bluetooth) sit on crDroid's / Evolution X's own frameworks with our
commits cherry-picked. `lineage-23.2` was deleted from GitHub on 2026-10-30 (bundle
backups exist). TWRP's only branch is `A16`.

### Branches

Each fix or feature goes on its own branch, `fix/<topic>` or `feature/<topic>` (`-24.0`
suffix), with the same name in every fork it touches; merges from LineageOS go on
`sync/lineage-<date>`. No pull requests for our own work. A branch is merged into
`lineage-24.0` once a build with it succeeds, then brought to both ports and deleted.
`manifests/malachite.xml` (LOS), `manifests/crdroid.xml` and `manifests/evolution.xml`
(on the port branches of the device tree) list every fork, its branch and what it changes.

- Local test build of 24.0 plus branches (WSL):
  `BRANCHES="fix/a feature/b" bash /mnt/e/LineageOS-23.2-Malachite/tools/build_lineage24.sh`.
- Server builds: see Building.

Kernel sources (not built; the ROMs use the prebuilt kernel): `kernel_manifest-6.1`
(`lineage-23.2`, Android-independent) owns `android_kernel_xiaomi_mt6878`,
`android_kernel_device_modules`, `android_vendor_mediatek_kernel_modules` and
`kernel-build-bazel_mgk_rules` under `malachite-project`.

Deliberately not forked: Aperture (replaced by Xiaomi Camera), XiaomiDolby (removed
after crashes), mt6878-devs `frameworks_av` (stale 23.0), `vendor_tms`
(unreferenced), `patches` (22.2). Backup only: `android_device_xiaomi_malachite_twrp`
(cmdr-chara's TWRP tree) -- **not safe** to flash as it is: its vendor_boot is
HyperOS-only and its boot HAL flips the UFS boot LUN, a hard-brick path.

Forks are never deleted: they are the backup if the original repositories
disappear. Chara's side branches were removed from them on 2026-10-10; they stay on
his account, and nothing the build needs lives only on them.

### Commit history and test status

On 2026-10-10 every fork's history was rewritten to drop the `[UNTESTED]` subject
prefixes and "Status: untested" lines (everything in them had shipped in builds
running on phones by then) and to set the "Build Machine" commits to Noam. The code
is byte-identical commit by commit; only messages and that identity changed. The
old-to-new hash map is in `notes/2026-10-10-history-rewrite-review.md`, and bundles
of the old history are in `E:\Android\Malachite\backups\malachite-repo-backup-20261010`. Hashes in notes
written before that date are the old ones.

New commits carry no status prefix. What was confirmed on the phone on the 23.2 line
(the 24.0 confirmations are in `HANDOFF.md`):

| Confirmed on the phone | Commits | Report |
| --- | --- | --- |
| Builds boot; NFC works after the signing fix | workspace `8684f00` | second build |
| Manual brightness, linear lights mapping | `3825136` | second build |
| Xiaomi colour modes | `1e83731`, `c91da2d` | second build |
| Unrounded backlight (one panel level per frame) | frameworks/base `f61033b4`, device `630873e` | third build |
| Slow auto-brightness ramps, darkening | `4458461`, `911942a` | fourth build |
| Three-finger screenshot | frameworks/base `138a22c8`, `fca7c902`, `8d92b671`, `374552ff`; Settings `b6464117` | fourth build |
| Charging control reaches the battery node | `006e18e`, `3270cb0` | fourth build |
| POCO X7 market name | `618b981` | first build |
| Passive USB-C adapter works | device `lineage-23.2` as of 20261009 | two testers, 2026-10-10 |

## Building

**Server (how releases are made now):** a ServerHive rental, one new account per day; the
user installs `~/.ssh/serverhive_malachite.pub` on it. Then, from Git Bash:

```
H=<user>@waffle.serverhive.in bash tools/server_run.sh malachite-24   # or evox, crdroid
```

It waits for key access, starts the build script in tmux from a login shell, sends the
release keys when the build asks (`server_send_keys.sh`, which arms `server_sign24.sh`
first: signed OTA, then every key copy deleted), and copies home the signed OTA and
boot/init_boot/vendor_boot. `tools/package_server_build.sh lineage|evox|crdroid <folder>
<yyyymmdd>` makes the release folder (zip, images, MindTheGapps for ROMs without Google
apps, FLASHING.md, SHA256SUMS.txt, tree-state.txt; logs to `builds\_logs`). At most two
ROM source trees on a rental at a time.

**Local (WSL):** `tools/build_lineage24.sh` builds 24.0 in
`/mnt/wsl/malachite-build/lineage-24` (`SYNC=1` resyncs, `BRANCHES=...` merges test
branches); inline signing with `tools/setup_inline_keys.sh` (keys from `tools/make_keys.sh`,
never pushed). Follow it with:

```
wsl bash /mnt/e/LineageOS-23.2-Malachite/tools/build_status.sh
```

Every build is the release type: `ro.debuggable=0`, ADB authorisation on (the debuggable
"tester" type was removed on 2026-10-26; `DIAGNOSTIC=1` only for a bootloop).

Flashing: fastboot boot/init_boot/vendor_boot, then in recovery sideload the ROM, reboot to
recovery, sideload MindTheGapps 17 (not for Evolution X), reboot. Updating from LineageOS
23.2 keeps data. Root (KernelSU-Next LKM, NoMount) is added by the user after each flash.

## Tests

The device tree has no unit tests any more (removed on 2026-10-27): changes are verified by
building and by tester reports. The tools below have their own tests (`tools/test_*`).

## Tools

| Tool | Purpose |
| --- | --- |
| `build_lineage24.sh` | Build 24.0 in WSL (see Building); `build_malachite.sh` is the retired 23.2 build |
| `server_run.sh`, `server_build24.sh`, `server_build_evox.sh`, `server_build_crdroid.sh`, `server_send_keys.sh`, `server_sign24.sh` | Server builds of LineageOS, Evolution X and crDroid (see Building) |
| `package_server_build.sh` | Release folder from a server build |
| `prepare_tree.sh` | Put a tree on its base branch (`BASE=lineage-24.0`) plus the named branches |
| `build_disk.sh` | Attach (`up`), check (`status`) or release (`down`) the build tree on the C: SSD |
| `make_build_disk_rootfs.sh`, `migrate_build_disk.sh` | One-time setup of the SSD build disk |
| `build_status.sh` | Follow the newest build until the signed OTA exists or it fails |
| `setup_inline_keys.sh` | Install our keys for inline signing in the WSL tree |
| `check_inline_signing.py` | Compare a build's signatures with the last release before it is flashed |
| `package_build.sh` | Make the OTA from signed target files and archive it (release folders also get boot images and SHA256SUMS.txt) |
| `sign_build.sh` | Re-sign target files with our keys (only without inline signing), check `mac_permissions`, then `package_build.sh` |
| `make_keys.sh` | Create the signing keys (LineageOS wiki) |
| `check_shared_uid_signers.py` | Shared UIDs with mixed signers in a signed target-files zip (`test_check_shared_uid_signers.py`) |
| `signer_inventory.sh` | Read-only signer check on the phone before a dirty flash |
| `preflash_check.sh` | Everything to check on the phone before flashing; compares its fstab with the tree |
| `collect_logs.sh` | Pull logs off the phone after a bootloop, freeze or reboot |
| `feature_check.sh` | On-phone evidence for HDR, QR, camera modes, Widevine |
| `policy_check_vendor.py`, `policy_check_writes.py` | Static SELinux checks of init services, init writes, powerhint nodes and grants |
| `sim_ambient_lux.py` | Port of the framework's ambient-lux logic (debounce, horizon, hysteresis) |
| `sim_auto_brightness.py` | The whole auto-brightness chain on everyday scenarios, read from the device tree |
| `find_wpa_version_site.py`, `test_wpa3_module.sh`, `test_wpa3_robustness.py`, `test_pmf.sh` | WPA3 module: locate and test the supplicant patch |
| `make_ksu_module.py`, `make_perf_module.py`, `test_perf_module.sh` | Build and test the KernelSU modules |

## KernelSU modules

For chara's release only (historical); our builds carry the fixes in source.

| Module | What it does |
| --- | --- |
| `malachite-wpa3-fix` (v1.5, v2.0) | WPA3 association fix (`notes/2026-09-21-wpa3-sae.md`) |
| `malachite-performance` (v1.0) | Stock-like CPU setup: sugov_ext, cpuqos, ADPF hints |
| `malachite-memory` (v1.0) | Stock Xiaomi low-memory-killer swap threshold |
| `malachite-offmode-flag` (v1.2) | Off-mode charging test: keeps `power_off_mode` at 1 after boot and logs what the bootloader saw (`notes/offmode-charging-test-plan.md`) |
| `malachite-offmode-test` (v1.0) | Obsolete test of a reboot-reason approach the bootloader ignores (`notes/2026-09-29-offmode-charging-flag.md`) |
| `rro/` | Overlay turning off Wi-Fi's WPA2-to-WPA3 auto-upgrade, for the WPA3 module |

## Notes

Newest first: [2026-10-31 tester report, fixes, syncs and server builds](notes/2026-10-31-los24-tester-report.md),
[Evolution X port](notes/2026-10-29-evolutionx-port.md), [crDroid port](notes/2026-10-29-crdroid17-port.md),
[crDroid / Evolution X review](notes/2026-10-30-crdroid-evox-review.md),
[FOD and camera fixes](notes/2026-10-30-los24-bug-fixes.md).
Earlier investigation: [FOD, camera and performance](notes/2026-10-29-los24-fod-camera-performance.md).
Tester capture: [instructions](notes/tester-guide-los24-20261029.md), [ADB root PC launcher](tools/collect_los24_tester.ps1) and [phone collector](tools/collect_los24_tester.sh).

| Note | Topic |
| --- | --- |
| `2026-09-21-ecosystem-research.md` | Other malachite ROMs and trees |
| `2026-09-21-tree-audit.md` | Audit of chara's device tree |
| `2026-09-21-wpa3-sae.md` | WPA3 / SAE association failure and its fix |
| `2026-09-22-feature-checks.md` | Face unlock port, kernel comparison, feature checks |
| `2026-09-22-first-build-plan.md` | Plan and decisions for the first own build |
| `2026-09-22-independent-prebuild-review.md` | First pre-build review |
| `2026-09-22-key-migration.md` | Switching to our signed build without wiping |
| `2026-09-22-performance-research.md` | Performance and battery research |
| `2026-09-22-upstream-review.md` | mt6878-devs and puhboo repositories |
| `2026-09-23-prebuild-checks.md`, `2026-09-23-first-build-manifest.xml` | Pre-build checks; the manifest of the first build |
| `2026-09-24-second-review.md` | Second independent review |
| `2026-09-26-three-finger-screenshot-offmode-charging.md` | Three-finger screenshot and off-mode charging, first look |
| `2026-09-27-final-prebuild-audit.md` | Final pre-build audit |
| `2026-09-27-hdr-wcg.md` | HDR10+ and wide colour |
| `2026-09-27-user-bug-reports.md` | User bug reports on chara's release |
| `2026-09-29-after-boot-checks.md` | Checks after the first boot |
| `2026-09-29-first-build-tester-report.md` | First build: tester report |
| `2026-09-29-offmode-charging-flag.md` | Off-mode charging: Xiaomi's `power_off_mode` flag |
| `2026-09-29-second-build-tester-report.md` | Second build: auto-brightness ramps, backlight precision, three-finger |
| `2026-09-30-third-build-tester-report.md` | Third build: darkening, three-finger density, off-mode flag timing, charging control |
| `2026-10-01-fourth-build-tester-report.md` | Fourth build: three-finger and darkening confirmed |
| `2026-10-01-auto-brightness-review.md` | Auto-brightness review before the release build |
| `2026-10-09-le-audio-research.md` | LE Audio: controller support, stock design, the Gerrit/duchamp sources, plan |
| `2026-10-10-misound-dolby.md` | MiSound still processing under Dolby; the HAL key and the Mi Sound switch |
| `2026-10-16-display-plan.md`, `2026-10-16-hdr-hwc-backlight.md` | Display work of the 23.2 release |
| `2026-10-22-user-bug-reports.md`, `2026-10-26-user-bug-reports.md` | User bug reports |
| `2026-10-23-*.md` | Brightness smoothing, camera, Codec2, HDR, LE Audio, music on wake, 480 Hz touch |
| `2026-10-25-*.md` | Branch workflow and build speed, LE Audio fixes, pocket wakes, auto-rotate |
| `2026-10-26-miface-port.md`, `2026-10-26-lineage24-bt-audio-module.md` | Stock face unlock port; 24.0 Bluetooth audio module |
| `2026-10-27-test24-build.md`, `2026-10-27-tester-reports.md` | First 24.0 builds and tester reports |
| `2026-10-29-*.md` | crDroid and Evolution X ports, LOS 24 FOD/camera/performance, Hunter ROM |
| `2026-10-30-*.md` | crDroid/Evolution X review, LOS 24 bug fixes, touch-rate review |
| `2026-10-31-*.md` | Tester report, Ultra HD and slider fixes, port parity, server builds; Rising PR review |
