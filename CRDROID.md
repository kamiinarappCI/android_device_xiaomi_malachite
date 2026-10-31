# crDroid 13 for malachite

crDroid 13.0 (Android 17) for malachite, on crDroid's `17.0` sources. It started
from the LOS24 device stack of 2026-10-28, is kept level with `lineage-24.0`, and
keeps the stock kernel, firmware blobs and restricted source ID. First release:
2026-10-31 (build ID CP2A.260605.016).

`lineage_malachite.mk` registers the `lineage_malachite` product, the prefix
used by crDroid's build tools; the file keeps that name because the build
finds a product's makefile by its PRODUCT_NAME. Stock mifaced supplies face unlock; the
alternative crDroid face service is not selected.

Use `manifests/crdroid.xml` with the crdroidandroid/android `17.0` manifest.
The manifest selects the matching `crdroid-17.0` branches in the
malachite-project forks, including the framework support commits ported
onto crDroid. All of them are published.

The crDroid three-finger gesture is retained. The LOS24 screenshot flash
control, brightness durations, precise backlight, call-volume handling,
FPSGO, GPU ABI fixes, shared SIM/eSIM, refresh-rate safeguards, LE Audio
fixes and optional battery saver CPU limit are carried over.

crDroid ships no Google apps: flash the Android 17 MindTheGapps after the ROM, as
on LineageOS.

## Building notes

- `breakfast malachite userdebug` (release type, as on LineageOS); sign with the
  same release keys as `lineage-24.0` (vendor/lineage-priv, loaded by crDroid's
  vendor config).
- Make the OTA from the extracted target files folder, as crDroid's own
  `otapackage` does (`out/.../target_files_intermediates/lineage_malachite-target_files`):
  crDroid's releasetools find partitions only in a folder and fail on the zip with
  `KeyError: 'system'`.
- 2026-10-31: compiled and signed; the first attempt had stopped at product lookup
  while the makefile was still named `crdroid_malachite.mk`.
