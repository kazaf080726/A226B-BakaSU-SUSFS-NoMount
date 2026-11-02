# 功能清单 / Feature inventory

本文件是"这个内核到底改了什么、每个功能落在哪个文件、怎么验证"的权威清单。
内核基线是三星官方 `SM-A226B_13_Opensource`（已逐字节校验，见文末），
所有改动都能用 `git diff cab987c8c HEAD` 精确复现。

```
Layer 0  三星原厂 Linux 4.14.186（MT6833 / a22x，未改）
Layer 1  SUSFS v2.3.0（NON-GKI 4.14 移植）      fs/susfs.c + 14 个内核文件
Layer 2  BakaSU 内联钩子（7 个）                  fs/exec.c 等
Layer 3  NoMount v2.2.0（VFS 重定向）           fs/nomount -> NoMount/kernel/src
Layer 4  PathMask 4.14 移植 + procguard（LKM）   pathmask/
Layer 5  KPM（镜像级，不改源码）                 ci/kpm_patch.sh
Layer 6  本项目自研反检测（2 处，非上游）         kernel/sys.c, block/ioprio.c, fs/proc/root.c
Layer 7  defconfig / AnyKernel3 / CI
```

## 1. SUSFS v2.3.0（`CONFIG_KSU_SUSFS`）

核心实现 `fs/susfs.c`（1558 行）+ `include/linux/susfs.h` + `include/linux/susfs_def.h`。
版本串见 `include/linux/susfs.h` 的 `SUSFS_VERSION "v2.3.0"`，`SUSFS_VARIANT` 在 4.14 上是 `NON-GKI`。

| 功能 | 开关 | 生效点（文件:行） | 作用 |
|---|---|---|---|
| SUS_PATH | `CONFIG_KSU_SUSFS_SUS_PATH` | `fs/readdir.c:157,286,408,533,652`、`fs/namei.c:1652,1715,1765,1821,1905,2322,3405` | inode 打 `AS_FLAGS_SUS_PATH`，readdir 过滤 + 名字查找返回 ENOENT |
| SUS_MOUNT | `CONFIG_KSU_SUSFS_SUS_MOUNT` | `fs/namespace.c:213,914,1262,1336`、`fs/super.c:992`、`fs/proc_namespace.c:475,486,497`、`fs/proc/fd.c:85` | KSU 的挂载打标 + 伪造 `mnt_id`/`mnt_group_id`，`/proc/mountinfo` 与 `fdinfo` 不暴露 |
| SUS_KSTAT | `CONFIG_KSU_SUSFS_SUS_KSTAT` | `fs/stat.c:95,207`、`fs/statfs.c:103,125`、`fs/notify/fdinfo.c:111`、`fs/proc/fd.c:68` | 伪造 ino/dev/nlink/size/atime/mtime/ctime/blocks |
| SPOOF_UNAME | `CONFIG_KSU_SUSFS_SPOOF_UNAME` | `kernel/sys.c:1246,1256` | 伪造 `uname()` 的 release/version |
| SPOOF_CMDLINE | `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | `fs/proc/cmdline.c:9,16` | 伪造 `/proc/cmdline` |
| OPEN_REDIRECT | `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | `fs/namei.c:3778,3834,3903,5151,5185`、`fs/proc/base.c:1742` | 打开路径重定向 + readlink 伪名 |
| SUS_MAP | `CONFIG_KSU_SUSFS_SUS_MAP` | `mm/memory.c:4983`、`fs/proc/task_mmu.c:394,865,1771`、`fs/proc/base.c:2316` | maps/smaps/map_files 隐藏真实文件 |
| HIDE_KSU_SUSFS_SYMBOLS | `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | `kernel/kallsyms.c:659-676` | 从 `/proc/kallsyms` 过滤 ksu/susfs 符号 |
| AVC log spoofing | 运行时命令 | `security/selinux/avc.c` | SELinux avc 拒绝日志脱敏 |
| ENABLE_LOG | `CONFIG_KSU_SUSFS_ENABLE_LOG` | `fs/susfs.c` | static_key 控制的日志开关 |

用户态接口是 SUSFS 的 ioctl 命令族（`CMD_SUSFS_*`，见 `include/linux/susfs_def.h`），
由 susfs4ksu 模块在开机时下发。

## 2. BakaSU 内联钩子

BakaSU（`Baka-SU/BakaSU`）在编译期会用 `kernel/tools/inline_hook_check.mk` 逐个校验钩子存在，
缺一个就 `$(error)` 直接失败——所以构建通过就等于钩子齐全。当前 7 个：

| 钩子 | 文件:行 |
|---|---|
| `ksu_handle_setresuid` | `kernel/sys.c:635,651` |
| `ksu_handle_execveat` / `_sucompat` / `_post_execveat_sucompat` | `fs/exec.c:1710,1736,1876` |
| `ksu_handle_faccessat` | `fs/open.c:372,440` |
| `ksu_handle_sys_read` | `fs/read_write.c:581,592` |
| `ksu_handle_stat` / `_vfs_fstat` | `fs/stat.c:29,32,207,264` |
| `ksu_handle_sys_reboot` | `kernel/reboot.c:286,297` |
| `ksu_handle_input_handle_event` | `drivers/input/input.c:371,380` |

构建时另有 `susfs_compat.mk` 探测 `security/selinux/hooks.c` 的 `ksu_selinux_hide_running`
和 `fs/exec.c` 的 `ksu_install_su_fd`，据此切换兼容宏；本内核两者都不存在（走 post_execveat 路线）。

## 3. NoMount v2.2.0（`CONFIG_NOMOUNT`）

- 源码通过 symlink 引入：`fs/nomount -> ../NoMount/kernel/src`（`fs/Kconfig`/`fs/Makefile` 里加了 `CONFIG_NOMOUNT`）
- 纯 VFS 层实现：劫持 `inode_operations`/`file_operations`/`iterate_dir`，构造虚拟目录树（`nm_leaf`/`nm_dir_node`/`nm_rule`）
- **用户态入口不是 syscall**：注册 `key_type "nomount"`，用户态用 `add_key()` 把 payload 地址传进来，
  `nm_key_preparse()` → `nm_process_payload()`（要求 `CAP_SYS_ADMIN`，恒返回 `-ECANCELED` 因此不留下 key）
- 内部命令码 `NM_CMD_*`，含 `NM_CLEAR_UIDS`/`NM_CLEAR_RULES`/`NM_CLEAR_EXIT`
- `fs_initcall(nomount_init)` 注册；UID 维度支持 `nm_block_isolated_uids`（90000-99999）

## 4. PathMask 4.14 移植（LKM，`pathmask/`）

上游 Andrea-lyz/LKM-PathMask v2.8.3 的 4.14 Non-GKI 移植：**保留上游 KernelSU 模块外壳**
（`service.sh`、WebUI、全部 conf），只替换内核态 `.ko`。

- 钩点下沉：`__inode_permission`（4.14 里 `inode_permission` 只是薄包装）、`vfs_getattr_nosec`、`SyS_getdents64`
- 去掉 KallRecon/KMSDK 依赖，直接用 4.14 已导出的 `kallsyms_lookup_name`/`kern_path`/`path_put`
- syscall 兜底前缀 `SyS_*`；`faccessat2`/`openat2` 在 4.14 不存在会自动跳过，`openat` 因缺 `close_fd` 注册阶段跳过
- 两次关键修复（见 git log）：
  - `getdents` 的 `kmalloc(GFP_KERNEL)` → `GFP_ATOMIC`（kretprobe 里睡会导致 SEC_DEBUG panic 重启）
  - 4.14 syscall ABI：`regs->regs[2]`（而不是 5.x 的 `user_regs->regs[2]`）
- 模块参数：`target_paths`、`hide_dirents`、`scope_mode`(global/deny/allow)、`deny_uids`、
  `enable_syscall_hooks`、`syscall_hooks`、`write_op_policy`(passthrough/eacces/enoent)
- 附带 `procguard.ko`：用 `in_group_p` kretprobe 去掉 gid 3009(AID_READPROC) 的隔离进程读取旁路

vermagic 必须与内核完全一致，所以 `.ko` 必须和内核同一次构建产出，不能跨版本混用。

## 5. KPM（KPatch-Next，镜像级）

`ci/kpm_patch.sh`：从源码编译 `kptools`（官方二进制要求更高 glibc），用 `kpimg-linux`
（固定 `KPATCH_TAG=0.13.5-2`）把补丁镜像追加进 `Image`，生成 `Image.kpm` / `Image.kpm.gz`，
并用 `kptools -l` 校验 `patched=true`。**不改内核源码**；与 `CONFIG_KPM=y` 的内置 KPM 互斥。

## 6. 本项目自研反检测（非上游）

1. `kernel/sys.c:198+` 与 `block/ioprio.c:62+`：当调用者是 app/isolated UID（10000-99999）时，
   对 `getpriority`/`setpriority`/`ioprio_get`/`ioprio_set` 里枚举的**其他** app(10000-19999) /
   isolated(90000-99999) UID 直接返回 `-ESRCH`。对抗"春秋 Native Check"扫 UID 找隐藏包。
2. `fs/proc/root.c:185`：`/proc/fs` 改成 root-only（`0500`），阻止检测器通过
   `/proc/fs/jbd2`、`/proc/fs/ext4` 判断存在 loop 挂载的 ext4 镜像。

### 6.1 关闭四个"全局可读"的泄漏（实机审计后补）

在真机上以非 root 身份逐项探测后发现，SUSFS/PathMask 把路径、挂载、stat 都藏住了，
但下面四处是**过宽的文件权限**造成的旁路，任何 App 都能直接读到：

| 泄漏 | 修复前 | 修复 |
|---|---|---|
| `/proc/version` | `0444`，打印真实 banner `4.14.186+ (A226B@a22x) ...` | `fs/proc/version.c` 在 SUSFS uname 伪造生效时改印伪造的 release/version |
| `/proc/config.gz` | `0444`，可直接读出 `CONFIG_KSU=y`/`CONFIG_NOMOUNT=y` | `kernel/configs.c` 改为 `0440` + 属组 `system`(1000)：system_server 的 `libvintf` 必须能读它做 VINTF 校验，App 仍读不到 |
| `dmesg` | `dmesg_restrict=0`，dmesg 中有 `KernelSU:`/`susfs:` 日志 | defconfig 打开 `CONFIG_SECURITY_DMESG_RESTRICT=y` |
| `/sys/module/{pathmask,procguard}/parameters/*` | `0644`/`0444`，能读到 `target_paths`/`deny_uids` 等**隐藏配置** | `pathmask/src/*.c` 里所有 `module_param*` 改为 `0400`；模块 service 与 WebUI 都以 root 运行，功能不受影响 |

同时补了两处符号层面的收敛（见第 2 节末尾）：`/proc/kallsyms` 增加 `_ksu_` / `.ksu_` / `susfs`
子串过滤；`/proc/modules` 对 app UID 隐藏 `pathmask`/`procguard`。

**仍然存在**：`/sys/module/pathmask`、`/sys/module/procguard` 这两个**目录名**本身仍可见
（参数值已不可读）。改名会同时失效 WebUI 里 `MODULE_NAME` 的 sysfs 读取路径，未做。

## 7. defconfig（`arch/arm64/configs/a22x_defconfig`）

- `# CONFIG_SECURITY_DEFEX is not set`（5557 行）——DEFEX 是三星机型 KernelSU 提权失败的头号原因
- 5834-5845 行追加：
  `CONFIG_KSU=y`、`CONFIG_KSU_SUSFS=y`、`SUS_PATH`、`SUS_MOUNT`、`SUS_KSTAT`、`SPOOF_UNAME`、
  `ENABLE_LOG`、`HIDE_KSU_SUSFS_SYMBOLS`、`SPOOF_CMDLINE_OR_BOOTCONFIG`、`OPEN_REDIRECT`、`SUS_MAP`、`CONFIG_NOMOUNT=y`
- 注意 `CONFIG_KSU_SUSFS` 在 BakaSU 的 Kconfig 里是 **choice**（与 `KSU_MANUAL_HOOK`/`KSU_TRACEPOINT_HOOK` 互斥），
  选了它才走 SuSFS Inline Hook 后端
- `CONFIG_THREAD_INFO_IN_TASK=y` 是 `CONFIG_KSU_SUSFS` 的硬依赖，本树满足

## 8. 打包（AnyKernel3）

`anykernel/anykernel.sh` 只做 `dump_boot` + `write_boot`，**不改 ramdisk**，只替换 boot 分区里的 kernel：

```
BLOCK=/dev/block/by-name/boot       # a22x 是 A-only，无 slot
IS_SLOT_DEVICE=0
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto
device.name1..4 = a22x / SM-A226B / a22xub / a22xeur
```

实机核对（SM-A226B / A226BZHSBDYA1）：boot 分区 `/dev/block/mmcblk0p41`，32 MiB，
Android boot header v2，page_size 2048，`kernel_addr=0x40080000`、`ramdisk_addr=0x51100000`、
`tags_addr=0x47c80000`、name `SRPTL28A011`、cmdline `bootopt=64S3,32N2,64N2 loop.max_part=7`。

## 9. 已知限制 / 未移植

- **priority UID filter**：上游 2026-10 新增，Non-GKI 4.14 补丁未包含（本项目的第 6 节是自己另做的等价实现）
- **SELinux 策略级 selinux_hide**：4.14 内部结构差异过大，只保留 avc 日志脱敏 + KSU 的 domain 处理
- **`/sys/module/{pathmask,procguard}` 目录名**仍对 App 可见（参数值已是 0400），改目录名会破坏
  WebUI 的 sysfs 读取路径，暂未处理

## 10. 运行时验证清单（在已 root 的设备上执行）

```sh
uname -a                                  # 应显示被 SUSFS 伪造的原厂串
cat /proc/version                         # 加固后应与 uname 一致（不再暴露 A226B@a22x）
su -c 'grep -c -e _ksu_ -e susfs /proc/kallsyms'  # 加固后期望 0
su -c 'ls -ld /proc/fs'                   # 期望 dr-x------ root root
ls -l /proc/config.gz                     # 加固后期望 -r--------
cat /proc/sys/kernel/dmesg_restrict       # 加固后期望 1
cat /sys/module/pathmask/parameters/target_paths   # 加固后作为 App 应 Permission denied
su -c 'cat /proc/modules' | grep -c -e pathmask -e procguard  # root 可见；App 应看不到
getenforce                                # 期望 Enforcing
cat /data/adb/pathmask/boot_state         # 期望 state=loaded
cat /data/adb/susfs4ksu/config.sh         # spoof_uname / avc_log_spoofing 等
```

## 附：基线校验方法

```sh
# 三星官方 zip 里的 Kernel.tar.gz 解包后与仓库 baseline 提交逐文件比对
git archive cab987c8c | tar -x -C /tmp/base
tar -xzf Kernel.tar.gz -C /tmp/stock
( cd /tmp/base  && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/a
( cd /tmp/stock && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/b
diff /tmp/a /tmp/b        # 实测：0 处内容差异（仅 3 个 DEFEX 生成物不在原厂包内）
```
