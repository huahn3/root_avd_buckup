---
name: root-avd
description: Use when working with Android Emulator AVD root, Magisk, Zygisk, LSPosed, or the backup/restore/shrink scripts in this repo (rootAVD.sh, pack_avd_full.sh, unpack_avd_full.sh, shrink_avd.sh, ramdisk.img, Pixel_8.avd). Covers rooting an AVD, backing up or restoring a rooted AVD, reclaiming qcow2 disk bloat, and the known traps that silently break each flow.
---

# rootAVD — Android Emulator Root & AVD Backup Toolchain

Personal fork of upstream [rootAVD](https://gitlab.com/newbit/rootAVD) (GPLv3) by
[newbit @ xda-developers](https://forum.xda-developers.com/m/newbit.1350876).
Two independent toolchains live here. Read `AGENTS.md` in the repo root first —
it is the canonical onboarding doc and this skill assumes it.

## Two independent chains — do not conflate them

| | Restore archive | `rootAVD.sh` |
|---|---|---|
| Requires | the 13G `.tar.zst` on NAS | this repo only |
| Result | your apps, login states, Magisk modules | a clean root environment |
| Root source | pre-patched `ramdisk.img` in archive | patches on the spot |
| Use for | recovering your environment | new AVD, or re-root after a brick |

**The GitHub repo does not contain AVD data.** The 13G archive holds app data and
account tokens, so it must never be committed. It lives on NAS.

## Environment

Mac mini / arm64 / macOS 27.0. AVD `Pixel_8`, Android 14 (API 34),
`google_apis_playstore`, `arm64-v8a`. emulator 37.1.11.0, Magisk v26.4 (26400),
Zygisk + LSPosed. `ANDROID_HOME=$HOME/Library/Android/sdk`.

## Commands

```bash
# backup / restore / shrink
./pack_avd_full.sh [dest]              # default: NAS, ~2 min
./unpack_avd_full.sh <archive.tar.zst> # one-click restore, ~4 min
./shrink_avd.sh                        # reclaim qcow2 bloat, ~6 min

# root an AVD (must run on the macOS host, never inside the emulator shell)
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
./rootAVD.sh system-images/android-34/google_apis_playstore/arm64-v8a/ramdisk.img
./rootAVD.sh ListAllAVDs   # prints every command variant
```

The first argument is the **ramdisk.img path relative to `$ANDROID_HOME`**, not a
directory. Options stack freely: `DEBUG` `PATCHFSTAB` `GetUSBHPmodZ` `FAKEBOOTIMG`
`InstallKernelModules` `restore`.

## Traps that silently break things

1. **`lib/*/libbusybox.so` is a hard dependency of root.** `FindWorkingBusyBox()`
   iterates `lib/*/*busybox*`; if absent, the loop body never runs and the script
   calls `abort_script`. Upstream `.gitignore` excluded these, so a fresh clone
   could never root. This repo tracks them — **do not re-add `libbusybox*` to
   `.gitignore`.**

2. **A physical phone on adb hijacks un-targeted commands.** With WiFi debugging
   on, `adb devices` lists both `emulator-5554` and `192.168.x.x:5555`. A bare
   `adb shell` hits the **phone**, producing false "emulator has no root" and
   "wrong app count" readings. Always use `adb -s emulator-5554 shell ...`.

3. **Offline rooting consumes `Magisk.zip`.** `rename_copy_magisk()` runs
   `mv Magisk.zip Magisk.apk` when `MAGISKVERCHOOSEN` is false, deleting the
   tracked `Magisk.zip`. Recover with `git checkout Magisk.zip`.

4. **`rootAVD.sh` must run on the host.** It probes `getprop` to detect whether it
   is inside an emulator shell and bails out. Run it from macOS.

5. **Android 14 has no `fstrim`**, so the host qcow2 never shrinks on its own.
   Only `qemu-img convert` dropping unallocated clusters reclaims space. Note
   `qemu-img convert -c` barely helps (measured: 0.44% of clusters compressed) —
   the win is entirely from discarding free clusters.

6. **`fastboot.forceFastBoot=yes` is the root cause of qcow2 bloat** — the
   quick-boot internal snapshot forces every write through COW.
   `shrink_avd.sh` disables it; the cost is a ~20s cold boot.

7. **`emulator@<old version>` is no longer installable.** Google's repo serves
   only the latest emulator, and an incompatible new one can silently produce a
   restored AVD **without root**. The backup archive therefore ships the
   emulator binary itself, and `unpack_avd_full.sh` prefers it over sdkmanager.

## Verifying root actually took

```bash
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell 'su -c id'     # must show uid=0 ... context=u:r:magisk:s0
adb -s emulator-5554 shell 'magisk -V'    # 26400
adb -s emulator-5554 shell 'su -c "ls /data/adb/modules"'   # zygisk_lsposed
```

`context=u:r:magisk:s0` is the only proof that Magisk took over. Never trust a
script's "✅ success" message alone — the old `unpack_avd_from_nas.sh` printed
success while silently failing.

## Discipline for agents

- Back up `rootAVD.sh` before editing; it is a ~3000-line upstream script and bulk
  `sed` replacements break it easily.
- Back up before deleting anything from `~/.android/avd/`, and confirm the NAS
  archive passes `zstd -t` first.
- Verify a restore by **booting the emulator and checking root + app count**,
  not by reading script output.
- `pack_avd_full.sh` / `unpack_avd_full.sh` intentionally refuse to run while the
  emulator is running; that message is expected — kill it with
  `adb -s emulator-5554 emu kill` first.
