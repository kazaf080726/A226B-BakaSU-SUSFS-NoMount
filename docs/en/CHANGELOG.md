> 🌐 **English** | [中文（默认）](../CHANGELOG.md)

# Changelog

Newest first. Every individual change is in `git log`; per-feature hooks and verification are in
[FEATURES.md](FEATURES.md).

## Unreleased — v1.4.0

### Reproducible builds
- Pin `KBUILD_BUILD_{USER,HOST,VERSION}`; take `KBUILD_BUILD_TIMESTAMP` from the version-controlled
  `ci/repro-date.txt` (never the clock or the commit time, otherwise a pre-commit build and a CI build
  can never match)
- Pin `LOCALVERSION=`: `scripts/setlocalversion` appends `+` unconditionally when HEAD has no annotated
  tag, so `uname -r` was permanently `4.14.186+`; it is now stable at `4.14.186`
- Measured: two full `rm -rf out` builds of the same tree produce a byte-identical `Image` / `Image.gz`
- Remove stale `arch/*/include/generated` and `include/generated` from the source tree before a
  from-scratch build, otherwise an `O=out` build skips regeneration and dies on
  `asm/types.h: file not found`
- Delete accidentally committed kbuild host products (`scripts/basic/fixdep`, `bin2c`,
  `scripts/unifdef`, `scripts/.*.cmd`, `pathmask/src/.tmp_versions/*.mod`): they are rewritten after
  every build and kept dirtying the worktree
- File modes: `README.md`, `NOTICE.md`, `.gitignore`, the workflow, `patches/README.md` and
  `pathmask/README.md` restored from 755 to 644

### CI / release
- Pin the upstream revisions: `BAKASU_REF` = `516d3e87…`, `NOMOUNT_REF` = `bf1847f…` (previously every
  build pulled `main`, which drifted from `d5e9e02` to `5785bdb8` to `516d3e87` within two days)
- Ship `dist/*.ko` as release assets
- Generate the release body from `build-info.txt` so it carries the revision actually used (the previous
  hand-written "Actual build in these assets" note was wiped by `overwrite: true`)

### Detection-leak hardening (driven by an on-device audit)
- `/proc/version` follows the SUSFS-spoofed `uname` (previously leaked `4.14.186+ (A226B@a22x)`)
- `/proc/sys/kernel/{osrelease,version}` follow the spoof too (previously **contradicted** `uname`)
- `/proc/config.gz` from `0444` to **`0440` with group `system`(1000)** (previously exposed
  `CONFIG_KSU=y`). An intermediate attempt used `0400`, which broke `libvintf` in system_server,
  failed VINTF verification and produced a "device internal problem" dialog at boot; corrected
- `CONFIG_SECURITY_DMESG_RESTRICT=y` (previously `dmesg_restrict=0` with `KernelSU:`/`susfs:` in dmesg)
- `/sys/module/{pathmask,procguard}/parameters/*` from `0644`/`0444` to `0400` (previously exposed
  `target_paths`, `deny_uids` and other hidden configuration)
- `/proc/kallsyms` filters the substrings `_ksu_` / `.ksu_` / `susfs` / `kernelsu` / `ksud`, covering all
  ten symbols that were still visible (including `__initcall_kernelsu_init6`)
- `/proc/modules` hides `pathmask` and `procguard` from app/isolated UIDs

### Reproducibility, continued (after comparing against CI byte by byte)

The first pass only achieved "two builds on the same machine agree". Comparing the CI artifacts
byte by byte exposed four more sources:

- **Linker build-id**: local and CI `Image` differed by 39 bytes (vDSO 19 + kernel 20) because a bare
  `--build-id` is unstable → `--build-id=none` for the vDSO and `LDFLAGS_BUILD_ID=` for vmlinux/modules
- **Absolute paths in the modules**: the `.ko` differed by ~1.3 KiB (`__FILE__` and DWARF carried the
  absolute build directory) → `KCFLAGS=-ffile-prefix-map=$ROOT/=`, plus `strip --strip-debug` before
  packaging (270 KB → 48 KB)
- **The zip archives themselves**: name and `build-info.txt` timestamp now come from `ci/repro-date.txt`;
  entry mtimes normalised with `zip -X`; entry order imposed by sorting names into `zip -@`; the whole
  packaging step runs under `TZ=UTC` (zip stores local wall-clock time)
- **`kernel/kheaders.ko`**: cpio kept the checkout mtimes and tar followed readdir order →
  `kernel/gen_kheaders.sh` now uses `touch -d` and `tar --sort=name --mtime=...`; the module has one
  remaining host dependency that cannot be removed, so it is no longer shipped

Result: two local builds, the CI build and the v1.4.0 release assets all produce the **same hashes for
all eight artifacts**.

### Documentation
- Add [FEATURES.md](FEATURES.md): each feature → implementing file/line → how to verify it
- Add [BUILD.md](BUILD.md): CI and local paths, reproducibility in depth, troubleshooting table
- Add this changelog, [RELEASE-v1.4.0.md](RELEASE-v1.4.0.md) (release notes draft),
  [XDA.md](XDA.md) (forum post draft) and [MAINTAINER-NOTES.md](MAINTAINER-NOTES.md)
- Make the documentation bilingual: Chinese stays the default, English mirrors live in `docs/en/`

## v1.3.1 — 2026-10-31

- `pathmask`: 4.14 syscall ABI fix (`regs->regs[2]` instead of the 5.x `user_regs->regs[2]`)
- `pathmask`: getdents buffer switched to `GFP_ATOMIC` and capped at 16 KiB (`GFP_KERNEL` inside a
  kretprobe caused a SEC_DEBUG panic and reboot)
- `ksu`: `getpriority`/`setpriority`/`ioprio_*` hide app/isolated UID enumeration
- `procfs`: `/proc/fs` made root-only (counters detection that inspects `/proc/fs/jbd2` and
  `/proc/fs/ext4` to infer a loop-mounted ext4 image)

## v1.2.0 — 2026-10-30

- Add the PathMask 4.14 port: `pathmask.ko` + `procguard.ko`, keeping the upstream KernelSU module shell
  (service.sh, WebUI, all configuration keys)
- CI builds the LKMs and uploads `A226B-PathMask-4.14-*.zip`
- `.gitignore` covers the PathMask build products

## v1.1.0 — 2026-10-30

- Add the KPM variant: kpimg from KPatch-Next `0.13.5-2` appended at image level (no kernel source change)
- `kptools` is now built from source (the official release binary needs a newer glibc than ubuntu-22.04 has)
- Releases ship both the standard and the KPM zip

## v1.0.1 — 2026-10-29

- Fix the AnyKernel3 boot partition path to `/dev/block/by-name/boot`

## Initial integration (no tag) — 2026-10-29

- Samsung `SM-A226B_13_Opensource` 4.14.186 stock source as the baseline (byte-identical to the official
  package)
- Integrate BakaSU (SUSFS inline hook), the 4.14 Non-GKI port of SUSFS v2.3.0 and NoMount v2.2.0
- Disable `CONFIG_SECURITY_DEFEX`
- AnyKernel3 packaging and GitHub Actions builds
