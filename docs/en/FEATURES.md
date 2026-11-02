> 🌐 **English** | [中文（默认）](../FEATURES.md)

# Feature inventory

This file is the authoritative answer to "what exactly does this kernel change, which file implements each
feature, and how is it verified". The baseline is Samsung's official `SM-A226B_13_Opensource` package
(byte-for-byte verified, see the appendix), so every change can be reproduced exactly with
`git diff cab987c8c HEAD`.

```
Layer 0  Samsung stock Linux 4.14.186 (MT6833 / a22x, unmodified)
Layer 1  SUSFS v2.3.0 (NON-GKI 4.14 port)        fs/susfs.c + 14 kernel files
Layer 2  BakaSU inline hooks (7)                  fs/exec.c and friends
Layer 3  NoMount v2.2.0 (VFS redirection)         fs/nomount -> NoMount/kernel/src
Layer 4  PathMask 4.14 port + procguard (LKMs)    pathmask/
Layer 5  KPM (image level, no source change)      ci/kpm_patch.sh
Layer 6  Project-specific anti-detection (2)      kernel/sys.c, block/ioprio.c, fs/proc/root.c
Layer 7  defconfig / AnyKernel3 / CI
```

## 1. SUSFS v2.3.0 (`CONFIG_KSU_SUSFS`)

Core implementation: `fs/susfs.c` (1,558 lines) + `include/linux/susfs.h` + `include/linux/susfs_def.h`.
The version string is `SUSFS_VERSION "v2.3.0"` in `include/linux/susfs.h`; `SUSFS_VARIANT` is `NON-GKI` on 4.14.

| Feature | Switch | Hook point (file:line) | Effect |
|---|---|---|---|
| SUS_PATH | `CONFIG_KSU_SUSFS_SUS_PATH` | `fs/readdir.c:157,286,408,533,652`, `fs/namei.c:1652,1715,1765,1821,1905,2322,3405` | tags the inode with `AS_FLAGS_SUS_PATH`, filters readdir and returns ENOENT on name lookup |
| SUS_MOUNT | `CONFIG_KSU_SUSFS_SUS_MOUNT` | `fs/namespace.c:213,914,1262,1336`, `fs/super.c:992`, `fs/proc_namespace.c:475,486,497`, `fs/proc/fd.c:85` | tags KernelSU mounts, forges `mnt_id`/`mnt_group_id`, hides them from `/proc/mountinfo` and fdinfo |
| SUS_KSTAT | `CONFIG_KSU_SUSFS_SUS_KSTAT` | `fs/stat.c:95,207`, `fs/statfs.c:103,125`, `fs/notify/fdinfo.c:111`, `fs/proc/fd.c:68` | forges ino/dev/nlink/size/atime/mtime/ctime/blocks |
| SPOOF_UNAME | `CONFIG_KSU_SUSFS_SPOOF_UNAME` | `kernel/sys.c:1246,1256` | forges release/version returned by `uname()` |
| SPOOF_CMDLINE | `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | `fs/proc/cmdline.c:9,16` | forges `/proc/cmdline` |
| OPEN_REDIRECT | `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | `fs/namei.c:3778,3834,3903,5151,5185`, `fs/proc/base.c:1742` | redirects open() paths and fakes readlink names |
| SUS_MAP | `CONFIG_KSU_SUSFS_SUS_MAP` | `mm/memory.c:4983`, `fs/proc/task_mmu.c:394,865,1771`, `fs/proc/base.c:2316` | hides the real file behind maps/smaps/map_files |
| HIDE_KSU_SUSFS_SYMBOLS | `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | `kernel/kallsyms.c:659-676` | filters ksu/susfs symbols out of `/proc/kallsyms` |
| AVC log spoofing | runtime command | `security/selinux/avc.c` | sanitises SELinux avc denial logs |
| ENABLE_LOG | `CONFIG_KSU_SUSFS_ENABLE_LOG` | `fs/susfs.c` | static_key controlled logging |

The userspace interface is SUSFS's ioctl command family (`CMD_SUSFS_*`, see
`include/linux/susfs_def.h`), issued by the susfs4ksu module at boot.

## 2. BakaSU inline hooks

At build time BakaSU (`Baka-SU/BakaSU`) checks every hook through
`kernel/tools/inline_hook_check.mk`; a missing one is a hard `$(error)`. A successful build therefore
means all hooks are present. There are currently seven:

| Hook | File:line |
|---|---|
| `ksu_handle_setresuid` | `kernel/sys.c:635,651` |
| `ksu_handle_execveat` / `_sucompat` / `_post_execveat_sucompat` | `fs/exec.c:1710,1736,1876` |
| `ksu_handle_faccessat` | `fs/open.c:372,440` |
| `ksu_handle_sys_read` | `fs/read_write.c:581,592` |
| `ksu_handle_stat` / `_vfs_fstat` | `fs/stat.c:29,32,207,264` |
| `ksu_handle_sys_reboot` | `kernel/reboot.c:286,297` |
| `ksu_handle_input_handle_event` | `drivers/input/input.c:371,380` |

At build time `susfs_compat.mk` also probes for `ksu_selinux_hide_running` in `security/selinux/hooks.c`
and `ksu_install_su_fd` in `fs/exec.c` and switches compatibility macros accordingly. Neither exists in
this tree, so the post_execveat route is used.

## 3. NoMount v2.2.0 (`CONFIG_NOMOUNT`)

- Pulled in through a symlink: `fs/nomount -> ../NoMount/kernel/src` (`CONFIG_NOMOUNT` added to
  `fs/Kconfig` and `fs/Makefile`)
- Pure VFS implementation: hijacks `inode_operations`/`file_operations`/`iterate_dir` and builds a
  virtual directory tree (`nm_leaf`/`nm_dir_node`/`nm_rule`)
- **The userspace entry point is not a syscall**: it registers `key_type "nomount"` and userspace passes
  a payload address through `add_key()`, then `nm_key_preparse()` → `nm_process_payload()` (requires
  `CAP_SYS_ADMIN`, always returns `-ECANCELED` so no key is retained)
- Internal command codes `NM_CMD_*`, including `NM_CLEAR_UIDS`/`NM_CLEAR_RULES`/`NM_CLEAR_EXIT`
- Registered through `fs_initcall(nomount_init)`; per-UID support through `nm_block_isolated_uids` (90000-99999)

## 4. PathMask 4.14 port (LKMs, `pathmask/`)

A 4.14 Non-GKI port of upstream Andrea-lyz/LKM-PathMask v2.8.3: the upstream KernelSU module shell is
**kept unchanged** (`service.sh`, WebUI, all conf files); only the kernel-side `.ko` is replaced.

- Hook points lowered: `__inode_permission` (`inode_permission` is only a thin wrapper on 4.14),
  `vfs_getattr_nosec`, `SyS_getdents64`
- Dropped the KallRecon/KMSDK dependency and used the 4.14-exported `kallsyms_lookup_name`/`kern_path`/`path_put`
- Syscall fallback prefix is `SyS_*`; `faccessat2`/`openat2` do not exist on 4.14 and are skipped
  automatically, `openat` is skipped during registration because `close_fd` is missing
- Two critical fixes (see git log):
  - `getdents` changed `kmalloc(GFP_KERNEL)` to `GFP_ATOMIC` (sleeping inside a kretprobe caused a
    SEC_DEBUG panic and reboot)
  - 4.14 syscall ABI: `regs->regs[2]` instead of the 5.x `user_regs->regs[2]`
- Module parameters: `target_paths`, `hide_dirents`, `scope_mode` (global/deny/allow), `deny_uids`,
  `enable_syscall_hooks`, `syscall_hooks`, `write_op_policy` (passthrough/eacces/enoent)
- Ships `procguard.ko`: an `in_group_p` kretprobe that removes the read bypass for isolated processes
  using gid 3009 (AID_READPROC)

vermagic must match the kernel exactly, so the `.ko` files have to come from the same build as the
kernel and cannot be mixed across versions.

## 5. KPM (KPatch-Next, image level)

`ci/kpm_patch.sh` compiles `kptools` from source (the official binary needs a newer glibc), appends the
patch image to `Image` using `kpimg-linux` (pinned `KPATCH_TAG=0.13.5-2`), produces `Image.kpm` /
`Image.kpm.gz` and verifies `patched=true` with `kptools -l`. **No kernel source change**; mutually
exclusive with the built-in `CONFIG_KPM=y`.

## 6. Project-specific anti-detection (not upstream)

1. `kernel/sys.c:198+` and `block/ioprio.c:62+`: when the caller is an app/isolated UID (10000-99999),
   `getpriority`/`setpriority`/`ioprio_get`/`ioprio_set` return `-ESRCH` for the *other* app (10000-19999)
   and isolated (90000-99999) UIDs. This counters detectors that scan UIDs to find hidden packages.
2. `fs/proc/root.c:185`: `/proc/fs` is made root-only (`0500`), so a detector cannot inspect
   `/proc/fs/jbd2` and `/proc/fs/ext4` to infer that a loop-mounted ext4 image exists.

### 6.1 Closing four world-readable leaks (added after a device audit)

Probing a real device as a non-root process showed that SUSFS/PathMask hide paths, mounts and stat
results, but four places leaked through **over-permissive file modes** that any app could read:

| Leak | Before | Fix |
|---|---|---|
| `/proc/version` | `0444`, printed the real banner `4.14.186+ (A226B@a22x) ...` | `fs/proc/version.c` prints the SUSFS-spoofed release/version when uname spoofing is active |
| `/proc/config.gz` | `0444`, exposed `CONFIG_KSU=y`/`CONFIG_NOMOUNT=y` | `kernel/configs.c` sets `0440` with group `system`(1000): system_server's `libvintf` must be able to read it for VINTF verification, while apps still cannot |
| `dmesg` | `dmesg_restrict=0`, dmesg contained `KernelSU:`/`susfs:` lines | defconfig enables `CONFIG_SECURITY_DMESG_RESTRICT=y` |
| `/sys/module/{pathmask,procguard}/parameters/*` | `0644`/`0444`, exposed `target_paths`/`deny_uids` and other **hidden configuration** | every `module_param*` in `pathmask/src/*.c` is now `0400`; the module service and WebUI run as root so nothing breaks |

Two symbol-level convrections were added at the same time (see the end of section 2): `/proc/kallsyms`
gained substring filtering for `_ksu_` / `.ksu_` / `susfs`, and `/proc/modules` hides
`pathmask`/`procguard` from app UIDs.

**Still present**: the *directory names* `/sys/module/pathmask` and `/sys/module/procguard` remain
visible (the parameter values do not). Renaming them would break the `MODULE_NAME` sysfs read path in
the WebUI, so this was left alone.

## 7. defconfig (`arch/arm64/configs/a22x_defconfig`)

- `# CONFIG_SECURITY_DEFEX is not set` (line 5557) — DEFEX is the number one reason KernelSU cannot gain
  root on Samsung devices
- Appended at lines 5834-5845: `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y`, `SUS_PATH`, `SUS_MOUNT`,
  `SUS_KSTAT`, `SPOOF_UNAME`, `ENABLE_LOG`, `HIDE_KSU_SUSFS_SYMBOLS`,
  `SPOOF_CMDLINE_OR_BOOTCONFIG`, `OPEN_REDIRECT`, `SUS_MAP`, `CONFIG_NOMOUNT=y`
- Note that `CONFIG_KSU_SUSFS` is a **choice** in BakaSU's Kconfig (mutually exclusive with
  `KSU_MANUAL_HOOK`/`KSU_TRACEPOINT_HOOK`); selecting it is what enables the SUSFS inline-hook backend
- `CONFIG_THREAD_INFO_IN_TASK=y` is a hard dependency of `CONFIG_KSU_SUSFS` and this tree provides it

## 8. Packaging (AnyKernel3)

`anykernel/anykernel.sh` only runs `dump_boot` + `write_boot`, **never touches the ramdisk**, and replaces
only the kernel inside the boot partition:

```
BLOCK=/dev/block/by-name/boot       # a22x is A-only, no slots
IS_SLOT_DEVICE=0
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto
device.name1..4 = a22x / SM-A226B / a22xub / a22xeur
```

Verified on a real device (SM-A226B / A226BZHSBDYA1): boot partition `/dev/block/mmcblk0p41`, 32 MiB,
Android boot header v2, page_size 2048, `kernel_addr=0x40080000`, `ramdisk_addr=0x51100000`,
`tags_addr=0x47c80000`, name `SRPTL28A011`, cmdline `bootopt=64S3,32N2,64N2 loop.max_part=7`.
The ramdisk was compared after flashing: 19/19 cpio entries with identical payloads (only cpio mode
bits are normalised by the repack).

## 9. Known limitations / not ported

- **priority UID filter**: added upstream in 2026-10 and not part of the Non-GKI 4.14 patch (section 6 of
  this project is an independent equivalent implementation)
- **SELinux policy level selinux_hide**: the 4.14 internals differ too much; only avc log sanitising and
  KernelSU's own domain handling are kept
- **`/sys/module/{pathmask,procguard}` directory names** are still visible to apps (values are `0400`);
  renaming them would break the WebUI sysfs read path, so it is not done yet

## 10. Runtime verification checklist (run on a rooted device)

```sh
uname -a                                  # should print the SUSFS-spoofed stock string
cat /proc/version                         # after hardening it must match uname (no A226B@a22x)
su -c 'grep -c -e _ksu_ -e susfs /proc/kallsyms'  # expect 0 after hardening
su -c 'ls -ld /proc/fs'                   # expect dr-x------ root root
ls -l /proc/config.gz                     # expect -r--r----- root system
cat /proc/sys/kernel/dmesg_restrict       # expect 1
cat /sys/module/pathmask/parameters/target_paths   # as an app: Permission denied
su -c 'cat /proc/modules' | grep -c -e pathmask -e procguard  # visible to root only
getenforce                                # expect Enforcing
cat /data/adb/pathmask/boot_state         # expect state=loaded
cat /data/adb/susfs4ksu/config.sh         # spoof_uname / avc_log_spoofing and friends
```

## Appendix: how the baseline is verified

```sh
# unpack Kernel.tar.gz from Samsung's official zip and compare file by file with the baseline commit
git archive cab987c8c | tar -x -C /tmp/base
tar -xzf Kernel.tar.gz -C /tmp/stock
( cd /tmp/base  && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/a
( cd /tmp/stock && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/b
diff /tmp/a /tmp/b        # measured: 0 content differences (only 3 DEFEX build products are absent upstream)
```
