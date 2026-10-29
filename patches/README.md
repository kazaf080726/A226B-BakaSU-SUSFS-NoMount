# 集成改动说明 / Integration notes

本仓库基于三星官方开源包 `SM-A226B_13_Opensource` 中的 `Kernel.tar.gz`
（Linux 4.14.186，MT6833，a22x_defconfig）。

相对原厂源码的改动分为三部分：

## 1. SUSFS v2.3.0（4.14 Non-GKI 移植）

基线补丁来自（GPL-2.0）：

- https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd
  文件：`Patches/Patch/susfs_patch_to_4.14.patch`（SUSFS v2.3.0）
- 该补丁由 simonpunk 的 `gki-android12-5.10` 分支深度移植到 4.14

应用方式：在 4.14.186 源码根目录 `patch -p1 < susfs_patch_to_4.14.patch`，
随后对 4 个文件（fs/notify/fdinfo.c、fs/proc/task_mmu.c、fs/super.c、
fs/namespace.c）的拒绝 hunk 做了 4.14.186 适配。

## 2. KernelSU/BakaSU 内联钩子

使用同一项目提供的 `Patches/susfs_inline_hook_patches.sh`（SUSFS v2.3 版）
给以下文件加入 BakaSU 需要的钩子：

- fs/exec.c            ksu_handle_execveat / _sucompat / post
- fs/open.c            ksu_handle_faccessat
- fs/read_write.c      ksu_handle_sys_read
- fs/stat.c            ksu_handle_stat / ksu_handle_vfs_fstat
- fs/namei.c           filename_lookup 导出
- drivers/input/input.c ksu_handle_input_handle_event
- kernel/reboot.c      ksu_handle_sys_reboot
- security/selinux/hooks.c  init -> su domain 放行

额外手工修改：

- kernel/sys.c：`ksu_handle_setresuid()` 钩子（脚本因当时未 clone
  `drivers/kernelsu` 而跳过，这里补上）
- fs/read_write.c：BakaSU 的 `ksu_handle_sys_read()` 是 3 参数版本，
  调用处补 `&buf, &count`
- fs/proc/task_mmu.c：void 函数中的 `return 0` 改为 `return`
- fs/notify/fdinfo.c：`mask` 声明移到函数开头（C 语言 label 后不能跟声明）

## 3. NoMount v2.2.0

使用上游 `kernel/setup.sh` 集成：`fs/nomount -> ../NoMount/kernel/src`，
并在 `fs/Kconfig`、`fs/Makefile` 中加入 `CONFIG_NOMOUNT`。

## 4. defconfig

在 `arch/arm64/configs/a22x_defconfig` 末尾追加：

```
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_NOMOUNT=y
```

## 未移植

- priority UID filter（上游 2026-10 新增，Non-GKI 4.14 补丁尚未包含）
- SELinux 策略级 selinux_hide（4.14 SELinux 内部结构差异过大）

其余路径/挂载/stat/maps/uname/cmdline/open_redirect/avc 日志隐藏均已生效。
