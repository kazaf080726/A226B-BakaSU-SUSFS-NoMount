> 🌐 **English** | [中文（默认）](README.md)

BakaSU + SUSFS + NoMount kernel for Samsung Galaxy A22 5G (SM-A226B)
=========================================================================

Device: Samsung Galaxy A22 5G (a22x / SM-A226B, MediaTek MT6833)
Kernel: Linux 4.14.186 (Samsung open source package SM-A226B_13_Opensource)
Type: Non-GKI (arm64)

> **Free · Public · Actively maintained**
> Every source file and build artifact of this project is published free of charge and can be compiled by anyone.
> No paid builds, no paywall, no licence key. Maintenance policy and self-build instructions are in section 7;
> third-party licences are listed in [NOTICE.md](NOTICE.en.md).

1. Download and versions
------------------------
- Releases (recommended): https://github.com/kazaf080726/A226B-BakaSU-SUSFS-NoMount/releases
- Latest CI build: Actions -> Build SM-A226B kernel -> Artifacts of the most recent run
- v1.0.1: BakaSU `d5e9e02`, SUSFS `v2.3.0`, NoMount `bf1847f`
- Upstream drift between builds was reduced over several releases starting with v1.3.1; from **v1.4.0**
  the upstream revisions are **pinned**, and every release note lists the BakaSU / NoMount revision actually used
- Two zips have been shipped since v1.1.0: **standard** and **KPM**, see section 5

2. What is integrated
---------------------
1. BakaSU (a KernelSU fork with the SUSFS inline-hook backend for Non-GKI 4.14)
   - The kernel driver is cloned at build time and is not stored in this repository
   - The revision is **pinned** in the workflow through `BAKASU_REF` (currently `516d3e87`,
     i.e. `v4.2.0-rc3-86-g516d3e87`), so rebuilding the same kernel commit is byte-identical
   - To upgrade: change `BAKASU_REF`, or pass `bakasu_ref` when running the workflow manually
   - The commit actually used is written to the Actions log and to `build-info.txt` inside every zip

2. SUSFS v2.3.0 (ported from gki-android12-5.10 down to 4.14)
   - Uses the 4.14 port maintained by JackA1ltman/NonGKI_Kernel_Build_2nd
   - Enabled:
     * SUS_PATH            hide arbitrary paths / directory entries (readdir and name lookup)
     * SUS_MOUNT           hide KernelSU mounts, forge mnt_id / mnt_group_id
     * SUS_KSTAT           forge ino, dev, size in stat/statfs/fdinfo/maps/inotify
     * SPOOF_UNAME         forge the uname release/version
     * SPOOF_CMDLINE       forge /proc/cmdline
     * OPEN_REDIRECT       redirect open() paths
     * SUS_MAP             hide the real file behind an mmap (maps/smaps/map_files)
     * ENABLE_LOG          SUSFS logging
     * HIDE_KSU_SUSFS_SYMBOLS  remove ksu/susfs symbols from /proc/kallsyms
     * AVC log spoofing    sanitise SELinux avc log entries
     * SHOW_VERSION / SHOW_VARIANT / ENABLED_FEATURES query interfaces

3. Samsung DEFEX disabled (`CONFIG_SECURITY_DEFEX`)
   - DEFEX blocks executing su/ksud from /data, which is the usual reason KernelSU cannot gain root on
     Samsung devices. SELinux stays enabled; KNOX features are already lost once the bootloader is unlocked.

4. NoMount v2.2.0 (VFS path redirection framework)
   - Built into the kernel (`CONFIG_NOMOUNT=y`), no LKM involved
   - Revision **pinned** through `NOMOUNT_REF` (currently `bf1847f`), overridable with `nomount_ref`
   - Install the official NoMount metamodule on the userspace side (managed through its WebUI)

5. KPM support (optional variant, KPatch-Next)
   - `kptools` appends KPatch-Next's `kpimg` to the Image; at boot it takes over and provides the KPM
     (Kernel Patch Module) runtime. No kernel source changes, no LKM slot used
   - This is KPatch-Next's KPM, not the built-in `CONFIG_KPM=y`; the two are mutually exclusive
   - After flashing the KPM kernel, install KPatch-Next-Module (shipped in the release) and load `.kpm`
     files from its WebUI
   - kpimg/kptools are pinned to KPatch-Next `0.13.5-2`

6. PathMask 4.14 (optional KernelSU module)
   - 4.14 Non-GKI port of Andrea-lyz/LKM-PathMask v2.8.3, keeping the original service.sh, WebUI and
     configuration keys, with the kernel side rebuilt as a 4.14-compatible `pathmask.ko`
   - Hooks `__inode_permission`, `vfs_getattr_nosec` and `SyS_getdents64`, with the original
     stat/access/readlink syscall fallback retained
   - Ships `procguard.ko` (gid 3009 / AID_READPROC isolation fix)
   - The `.ko` files come from the same CI build as the kernel; vermagic/MODVERSIONS must match
   - Usage: flash the kernel, install `A226B-PathMask-4.14-*.zip`, then configure target paths/UIDs in its WebUI

3. Not ported / known limitations
---------------------------------
- priority UID filter (anti getpriority-abuse detection): added upstream in 2026-10 and not part of the
  Non-GKI 4.14 patch yet, so it is disabled here. The other hiding features are unaffected.
- Deep SELinux policy hiding (the kernel-policy part of selinux_hide): the SELinux internals differ too
  much on 4.14, so only avc log sanitising and KernelSU's own domain handling are kept.
- Because of those two gaps SUSFS is not 100% of upstream, but all the main hiding features work:
  paths, mounts, stat, maps, uname, cmdline, open_redirect and avc logs.
- Verified on a real SM-A226B: boots normally, SUSFS works, NoMount opens and takes effect. This is
  short-term verification; long-term stability still depends on real-world use. Back up the stock
  boot.img before the first flash and make sure the bootloader is unlocked.

4. Building
-----------
GitHub Actions (recommended):
  Actions -> Build SM-A226B kernel -> Run workflow
  Artifacts: standard AnyKernel3 zip, KPM AnyKernel3 zip, Image.gz / Image.kpm.gz,
             modules.zip, KPatch-Next-Module.zip

Locally (Ubuntu 22.04+ / WSL2):
  bash ci/fetch_toolchain.sh
  git clone https://github.com/Baka-SU/BakaSU.git KernelSU
  git -C KernelSU checkout 516d3e87fbc986ccefdde2c2765f1700612441a9   # same as BAKASU_REF
  git clone https://github.com/maxsteeel/nomount.git NoMount
  git -C NoMount checkout bf1847f98fed382369c43bfd652cd93774b9b8e3    # same as NOMOUNT_REF
  bash ci/build.sh
  bash ci/package.sh
  bash ci/kpm_patch.sh      # produces Image.kpm / Image.kpm.gz
  bash ci/package_kpm.sh    # produces the KPM AnyKernel3 zip

Toolchain: AOSP clang-r383902 + GCC 4.9 binutils, the same pair Samsung used.
KPM: kptools/kpimg from KPatch-Next 0.13.5-2, pinned inside the scripts.

Reproducible builds:
  `ci/build.sh` defaults to `REPRO=1`, which pins `KBUILD_BUILD_USER/HOST/VERSION`, takes
  `KBUILD_BUILD_TIMESTAMP` from `ci/repro-date.txt` (a version-controlled line; the cpio mtimes of
  the built-in initramfs follow it too) and sets `LOCALVERSION=` so that `setlocalversion` stops
  appending an unconditional `+` (the release string stays `4.14.186`). Together with pinned
  BakaSU/NoMount revisions and a pinned toolchain, **a local build and a CI build of the same commit
  produce a byte-identical Image** (verified over two full builds). `REPRO=0` restores the old
  behaviour. See [docs/BUILD.md](docs/en/BUILD.md) for the eight sources of drift and how each was removed.

5. Flashing
-----------
1. Unlock the bootloader (wipes data and permanently trips KNOX).
2. In TWRP, pick one:
   - normal use: flash A226B-BakaSU-SUSFS-NoMount-*.zip (standard)
   - KPM needed: flash A226B-BakaSU-SUSFS-NoMount-KPM-*.zip
3. Reboot; the first boot takes a while.
4. Install the BakaSU manager APK, then optionally the official NoMount metamodule.
5. For the KPM variant also install KPatch-Next-Module-v0.0.1.zip from the release and load `.kpm`
   files in its WebUI. Do not use its "patch boot" function.
6. PathMask: install `A226B-PathMask-4.14-*.zip` (a KernelSU module), reboot, then set target_path /
   scope_mode in its WebUI. Its `.ko` must match the kernel you flashed.
7. If it does not boot: restore the backed-up stock boot.img in TWRP, or flash the stock AP with Odin.
   For the KPM variant, flash the standard build first to rule KPM out.

Notes:
- The zip replaces only the kernel inside the boot partition; the stock ramdisk/dtb are kept.
- Standard and KPM are the same kernel source; only whether kpimg is appended differs. Do not mix
  modules between them: the KPM build requires KPatch-Next-Module.
- Samsung AVB/vbmeta may reject the modified boot image. AK3 ships PATCH_VBMETA_FLAG=auto; if it still
  does not boot, flash vbmeta_disabled as well (or use a TWRP build with verification disabled).
- KNOX features (Samsung Pay, Secure Folder, ...) are permanently lost.

6. Repository layout
--------------------
- The repository root is the kernel source tree (complete Samsung 4.14.186 plus the integration)
- drivers/kernelsu -> ../KernelSU/kernel (cloned at build time, not committed)
- fs/nomount      -> ../NoMount/kernel/src (cloned at build time, not committed)
- ci/             build scripts
- anykernel/      AnyKernel3 template
- pathmask/       PathMask 4.14 port plus the KernelSU module shell
- patches/        description of the integration relative to stock (see patches/README.md)
- docs/           feature list [docs/FEATURES.md](docs/en/FEATURES.md), build & reproducibility
                  [docs/BUILD.md](docs/en/BUILD.md), changelog [docs/CHANGELOG.md](docs/en/CHANGELOG.md),
                  release notes and XDA draft ([docs/RELEASE-v1.4.0.md](docs/en/RELEASE-v1.4.0.md),
                  [docs/XDA.md](docs/en/XDA.md)), maintainer notes
                  [docs/MAINTAINER-NOTES.md](docs/en/MAINTAINER-NOTES.md)

7. Maintenance, cost and self-building
--------------------------------------
- **Free forever**: sources, CI configuration and release artifacts are all public. There is no paid
  tier, no paid support and no licence key. Forking, self-building and redistribution are welcome.
- **Actively maintained**: BakaSU / NoMount are built from the revisions pinned in the workflow (bump
  `BAKASU_REF` / `NOMOUNT_REF` and run the full verification when upgrading); SUSFS is re-ported to
  4.14 when upstream changes; PathMask follows upstream 2.8.x; compatibility and security issues are
  fixed through Issues.
- **Self-build**: fork the repo -> Actions -> Build SM-A226B kernel -> Run workflow, or build locally
  as described in section 4. Artifacts land in Actions Artifacts; pushing a `v*` tag publishes a release.
- **Redistribution**: allowed under GPL-2.0 / GPL-3.0 (see [NOTICE.md](NOTICE.en.md)). Keep the origin and
  credits, and do not repackage this project as a paid exclusive build.
- **Scope of support**: no promise that every region/firmware boots; flashing is at your own risk. Even
  if maintenance stops, all sources and past releases stay in the repository.

8. Credits
----------
- BakaSU: https://github.com/Baka-SU/BakaSU
- SUSFS: simonpunk https://gitlab.com/simonpunk/susfs4ksu
- Non-GKI 4.14 SUSFS port: JackA1ltman
  https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd
- 4.14 Samsung integration reference: betelqeyza
  https://github.com/betelqeyza/android_kernel_samsung_universal9611
- NoMount: maxsteeel https://github.com/maxsteeel/nomount
- PathMask: Andrea-lyz https://github.com/Andrea-lyz/LKM-PathMask
- AnyKernel3: osm0sis https://github.com/osm0sis/AnyKernel3

GPL-2.0. Kernel source copyright belongs to Samsung and the respective authors.
