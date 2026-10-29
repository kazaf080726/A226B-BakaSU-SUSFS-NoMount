BakaSU + SUSFS + NoMount kernel for Samsung Galaxy A22 5G (SM-A226B)
=========================================================================

设备：Samsung Galaxy A22 5G (a22x / SM-A226B, MediaTek MT6833)
内核：Linux 4.14.186（Samsung 官方开源包 SM-A226B_13_Opensource）
类型：Non-GKI（arm64）

一、集成了什么
--------------
1. BakaSU（最新 main，构建时从 GitHub 拉取）
   - KernelSU 分支，支持 Non-GKI 4.14 的 SUSFS Inline Hook 模式
   - 每次 GitHub Actions 编译都会 clone 最新 main，并在日志/Release 中记录 commit

2. SUSFS v2.3.0（从 gki-android12-5.10 深度移植到 4.14 的版本）
   - 采用 JackA1ltman/NonGKI_Kernel_Build_2nd 维护的 4.14 移植补丁
   - 已启用：
     * SUS_PATH            隐藏任意路径/目录项（含 readdir、名字查找）
     * SUS_MOUNT           隐藏 KSU 挂载、伪造 mnt_id / mnt_group_id
     * SUS_KSTAT           stat/statfs/fdinfo/maps/inotify 伪造 ino、dev、size 等
     * SPOOF_UNAME          伪造 uname release/version
     * SPOOF_CMDLINE       伪造 /proc/cmdline
     * OPEN_REDIRECT       打开路径重定向
     * SUS_MAP             隐藏 mmap 的真实文件（maps/smaps/map_files）
     * ENABLE_LOG          SUSFS 日志开关
     * HIDE_KSU_SUSFS_SYMBOLS  从 /proc/kallsyms 隐藏 ksu/susfs 符号
     * AVC log spoofing    SELinux avc 日志脱敏
     * SHOW_VERSION / SHOW_VARIANT / ENABLED_FEATURES 查询接口

3. 已关闭 Samsung DEFEX（`CONFIG_SECURITY_DEFEX`）
   - DEFEX 会拦截从 /data 执行 su/ksud，是三星机型 KernelSU 无法提权的
     常见原因；关闭后 SELinux 仍然启用，KNOX 相关功能本来就会因解锁失效。

4. NoMount v2.2.0（VFS 路径重定向框架）
   - 内核原生集成（CONFIG_NOMOUNT=y），不使用 LKM
   - 用户态请安装 NoMount 官方 Metamodule（WebUI 管理）

二、没有移植 / 已知限制
-----------------------
- priority UID filter（getpriority 滥用检测对抗）：上游 2026-10 才加入，
  Non-GKI 4.14 补丁尚未包含，本内核未启用。不影响其它隐藏功能。
- SELinux policy 深度隐藏（selinux_hide 的内核策略级部分）：4.14 的
  SELinux 内部结构差异过大，只保留了 avc 日志脱敏与 KSU 自身的 domain 处理。
- 由于以上两项缺失，SUSFS 的“全部功能”并非 100%，但路径/挂载/stat/maps/
  uname/cmdline/open_redirect/avc 日志等主力隐藏功能全部生效。
- 本内核未在本机实机验证（只完成编译与符号校验）。首次刷入前请务必备份
  原厂 boot.img，并确认已解锁 BootLoader。

三、构建
--------
GitHub Actions（推荐）：
  Actions -> Build SM-A226B kernel -> Run workflow
  产物：AnyKernel3 zip、Image.gz、modules.zip

本地（Ubuntu 22.04+ / WSL2）：
  bash ci/fetch_toolchain.sh
  git clone https://github.com/Baka-SU/BakaSU.git KernelSU
  git clone https://github.com/maxsteeel/nomount.git NoMount
  bash ci/build.sh
  bash ci/package.sh

工具链：AOSP clang-r383902 + GCC 4.9 binutils（Samsung 原厂同款）。

四、刷入
--------
1. 解锁 BootLoader（会清空数据并熔断 KNOX，不可逆）。
2. 使用 TWRP（a22x 的第三方 recovery）刷入
   A226B-BakaSU-SUSFS-NoMount-*.zip。
3. 重启；首次开机较慢。
4. 安装 BakaSU 管理器 APK；再安装 NoMount 官方 Metamodule（可选）。
5. 若无法开机：进 TWRP 恢复备份的 stock boot.img，或 Odin 刷回原厂 AP。

注意：
- 本 zip 只替换 boot 分区中的 kernel，保留原厂 ramdisk/dtb。
- 三星 AVB/vbmeta 可能导致校验失败；AK3 已带 PATCH_VBMETA_FLAG=auto，
  如仍无法开机请同时刷入 vbmeta_disabled（或使用已禁用校验的 TWRP）。
- KNOX 相关功能（Samsung Pay、Secure Folder 等）会永久失效。

五、目录说明
------------
- 内核源码根目录即本仓库根目录（完整 Samsung 4.14.186 + 集成修改）
- drivers/kernelsu -> ../KernelSU/kernel（构建时 clone，不入库）
- fs/nomount      -> ../NoMount/kernel/src（构建时 clone，不入库）
- ci/             构建脚本
- anykernel/      AnyKernel3 模板
- patches/        本仓库相对原厂源码的集成改动说明（见 patches/README.md）

六、致谢
--------
- BakaSU: https://github.com/Baka-SU/BakaSU
- SUSFS: simonpunk https://gitlab.com/simonpunk/susfs4ksu
- Non-GKI 4.14 SUSFS 移植: JackA1ltman
  https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd
- 4.14 Samsung 集成参考: betelqeyza
  https://github.com/betelqeyza/android_kernel_samsung_universal9611
- NoMount: maxsteeel https://github.com/maxsteeel/nomount
- AnyKernel3: osm0sis https://github.com/osm0sis/AnyKernel3

GPL-2.0，内核源码版权归 Samsung / 各原作者所有。
