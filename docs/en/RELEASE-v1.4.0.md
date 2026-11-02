> 🌐 **English** | [中文（默认）](../RELEASE-v1.4.0.md)

# v1.4.0 — reproducible builds + detection-leak hardening

> This is the release-notes draft for **v1.4.0**. The actual revisions and hashes are always the ones in
> the `build-info.txt` of each build.

**Kernel**: Linux 4.14.186 (Samsung SM-A226B open source, baseline byte-verified)
**Components**: BakaSU `516d3e87`, SUSFS `v2.3.0` (4.14 non-GKI port), NoMount `bf1847f`,
KPatch-Next `0.13.5-2`, PathMask 2.8.x (4.14 port)

## Highlights

1. **Reproducible builds** — the same commit with the pinned dependencies and toolchain produces a
   byte-identical `Image`/`Image.gz` locally and on CI. Two sources of drift are pinned: the build
   metadata (`KBUILD_BUILD_*`, timestamp from a version-controlled file) and the release-string suffix
   (`LOCALVERSION=` suppresses the unconditional `+`). Comparing against CI afterwards removed six more
   sources (linker build-id, absolute paths in the modules, archive names/timestamps, zip entry order
   and timezone, gzip headers, the kheaders archive) — see [BUILD.md](BUILD.md).

2. **Pinned upstream revisions** — BakaSU `main` is no longer pulled at build time (it moved three times
   in two days, which silently changed the kernel behind a fixed tag). Both revisions live in
   `BAKASU_REF` / `NOMOUNT_REF` in the workflow.

3. **Detection-leak hardening (7 items)** — `/proc/version`, `/proc/sys/kernel/{osrelease,version}`,
   `/proc/config.gz`, `dmesg`, `/sys/module/*/parameters/*`, `/proc/kallsyms` and `/proc/modules` no
   longer hand a rooted-kernel fingerprint to unprivileged apps. Note that `/proc/config.gz` is
   `0440` with group `system`, not root-only: system_server's `libvintf` needs it for VINTF
   verification, and denying it produced a "device internal problem" dialog at boot.

## Verified artifacts

Release: https://github.com/kazaf080726/A226B-BakaSU-SUSFS-NoMount/releases/tag/v1.4.0

Local build, CI build and the published release assets are **byte-identical** (8/8):

```
Image.gz                                          5e4f6ed75d05a2862c090f65c4579f1c3d17050dca10b5d94db0e96d9553f05d
Image.kpm.gz                                      82ef4611f68dfbae265e36b5cdb5732980f32efd40ac7b45fea7184811f291bd
A226B-BakaSU-SUSFS-NoMount-20261102.zip           ea0575849b4eb73749d948001e1217df390af6d271e582db3030ce5195bcad9c
A226B-BakaSU-SUSFS-NoMount-KPM-20261102.zip       785ae18bd4b57b9e115207612f5a03fe8f7a53cc5971bd40dcf1b23bd7440134
A226B-BakaSU-SUSFS-NoMount-modules-20261102.zip   b0c3c87ace36293741367a9fa7fc42802c88acbb65aa58bcde1bd75d4d7d8709
A226B-PathMask-4.14-20261102.zip                  f367c0d27f13bad10876846e5d9d25bf36c577522eda8c654ff2dfe29e0e4f49
pathmask-4.14.ko                                  7b1e807ccf7bdf47aa60687aeca41b0b166bd6f1c3d9d2b9af8274ab4aa0bd65
procguard-4.14.ko                                 2149872afc3cfa9a6bbb1d0e02551c4bc70ca3974e852e161e0ca8e1d702e055
```

The boot partition was also read back from a flashed device: the kernel segment's sha256 equals
`Image.kpm.gz`, i.e. the phone runs exactly the published bytes.

## Flashing

1. Back up your stock `boot.img` first.
2. Flash `A226B-BakaSU-SUSFS-NoMount-*.zip` in TWRP (or the `-KPM-` variant if you need KPM; do not
   flash both).
3. PathMask users: flash the matching `A226B-PathMask-4.14-*.zip` from the same build — the `.ko`
   vermagic must match the kernel.
4. First boot takes a while.

## Known limitations

- The `/proc/sys/kernel/*` spoofing needs SUSFS `spoof_uname` to be active (susfs4ksu module).
- `/sys/module/{pathmask,procguard}` directory names stay visible to apps (values are not).
- SUSFS priority-UID filter and policy-level SELinux hiding are still not ported
  (see [FEATURES.md](FEATURES.md) section 9).
