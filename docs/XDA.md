# XDA post draft (English)

Use for the maintainer thread / release announcement. Numbers are from the v1.4.0 work;
regenerate the revision list from the release `build-info.txt` before posting.

---

## [KERNEL][4.14.186][A22 5G] BakaSU + SUSFS + NoMount for SM-A226B (a22x) — free & open source

**Device**: Samsung Galaxy A22 5G (SM-A226B / a22x, MediaTek MT6833)
**Kernel**: Linux 4.14.186, from Samsung's official `SM-A226B_13_Opensource` package
**Status**: boots on A226BZHSBDYA1 (Android 13), root + hiding stack working

### What's inside

- **BakaSU** (KernelSU fork) with the SUSFS inline-hook backend
- **SUSFS v2.3.0**, back-ported to 4.14 (non-GKI): sus_path, sus_mount, sus_kstat,
  spoof uname / cmdline, open_redirect, sus_map, AVC log spoofing, symbol hiding
- **NoMount v2.2.0** built into the kernel (VFS-level path redirection, no mounts involved)
- **PathMask 4.14 port** (`pathmask.ko` + `procguard.ko`) shipped as a KernelSU module
- **Optional KPM variant**: image patched with KPatch-Next kpimg, so `.kpm` modules load
- **Detection-leak hardening** on top of upstream SUSFS (see below)
- **Reproducible builds**: same commit + pinned revisions = byte-identical `Image`

### Why another kernel for this device

Samsung's DEFEX blocks `su`/`ksud` from `/data`, which is the usual reason KernelSU fails to
grant root on Samsung devices. DEFEX is disabled here (`CONFIG_SECURITY_DEFEX=n`); SELinux
stays enforcing.

### Detection-leak hardening

SUSFS hides paths, mounts and stat data, but a rooted kernel still answers some very simple
questions. Audited on a real device as an unprivileged process and closed:

| Probe | Before | Now |
|---|---|---|
| `/proc/version` | `4.14.186+ (A226B@a22x) ...` | mirrors the spoofed `uname` |
| `/proc/sys/kernel/osrelease` | `4.14.186+` (contradicted `uname`) | mirrors the spoofed `uname` |
| `/proc/config.gz` | world-readable, showed `CONFIG_KSU=y` | root-only |
| `dmesg` | readable, full of `KernelSU:`/`susfs:` | `dmesg_restrict=1` |
| `/sys/module/pathmask/parameters/*` | world-readable hidden-path config | root-only |
| `/proc/kallsyms` | 10 symbols containing `ksu`/`susfs` | filtered |
| `/proc/modules` | `pathmask`, `procguard` listed | hidden from app UIDs |

### Install

1. Unlock the bootloader (wipes data, trips KNOX — irreversible).
2. **Back up your stock `boot.img`.** If anything goes wrong, restore it in TWRP or via Odin.
3. Flash `A226B-BakaSU-SUSFS-NoMount-*.zip` in TWRP. Use the `-KPM-` zip only if you want KPM.
4. Install the KernelSU-compatible manager APK; install the NoMount metamodule if you use it.
5. PathMask: flash `A226B-PathMask-4.14-*.zip` from the **same build** — a `.ko` from another
   build will fail vermagic and refuse to load.

The zip replaces only the kernel inside the boot partition; stock ramdisk/DTB are kept.
`PATCH_VBMETA_FLAG=auto` is enabled by the AnyKernel3 template.

### Verified

- Boots on A226BZHSBDYA1, boot partition 32 MiB, Android boot header v2, page size 2048
- `susfs_` symbols: 0 visible in `/proc/kallsyms`; `uname` spoofed to the stock string
- `PathMask`/`procguard` loaded, `pathmask` boot state `loaded`
- Device `/proc/config.gz` matches the locally built `.config` exactly
- Two clean builds of the same commit produce identical `Image` hashes

### Known limitations

- SUSFS priority-UID filter and policy-level SELinux hiding are not ported to 4.14.
- `/sys/module/{pathmask,procguard}` directory names remain visible (values are not).
- KPM and standard builds must not be mixed with modules from the other variant.

### Credits

BakaSU (Baka-SU), SUSFS (simonpunk), 4.14 port (JackA1ltman), NoMount (maxsteeel),
PathMask (Andrea-lyz), KPatch-Next (KernelSU-Next), AnyKernel3 (osm0sis), Samsung for the
kernel source.

### Source & builds

Everything is public: kernel source, build scripts, CI workflow and the exact pinned
revisions. Fork it, run the workflow, build it yourself — no paid tier, no license keys.
GPL-2.0 applies to the kernel sources; upstream components keep their own licenses.

**Flashing is at your own risk. KNOX features (Samsung Pay, Secure Folder) are gone forever
once the bootloader is unlocked.**
