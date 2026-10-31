BakaSU + SUSFS + NoMount kernel for Samsung Galaxy A22 5G (SM-A226B)
=========================================================================

设备：Samsung Galaxy A22 5G (a22x / SM-A226B, MediaTek MT6833)
内核：Linux 4.14.186（Samsung 官方开源包 SM-A226B_13_Opensource）
类型：Non-GKI（arm64）

> **免费 · 公开 · 持续维护**
> 本项目所有源码与构建产物永久免费公开，可自行编译；不卖包、不设付费墙、不需要授权码。
> 维护策略与自编译方法见第七节，第三方代码许可见 [NOTICE.md](NOTICE.md)。

一、下载与版本
--------------
- Releases（推荐）：https://github.com/kazaf080726/A226B-BakaSU-SUSFS-NoMount/releases
- 最新 CI 构建：仓库 Actions -> Build SM-A226B kernel -> 最近一次 run 的 Artifacts
- v1.0.1：BakaSU `d5e9e02`、SUSFS `v2.3.0`、NoMount `bf1847f`
- v1.1.0 起同时提供 **标准版** 与 **KPM 版** 两种 zip，见下文第五节

二、集成了什么
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

5. KPM 支持（可选变体，KPatch-Next）
   - 用 kptools 把 KPatch-Next 的 kpimg 追加进 Image，内核启动时接管并
     提供 KPM（Kernel Patch Module）运行时；不改内核源码、不占用 LKM
   - 这是 KPatch-Next 的 KPM，不是 `CONFIG_KPM=y` 的内置 KPM；两者互斥
   - 刷 KPM 版内核后，再安装 KPatch-Next-Module（Release 里附带），
     用它的 WebUI 加载 `.kpm`
   - 固定使用 KPatch-Next `0.13.5-2` 的 kpimg/kptools

6. PathMask 4.14（可选 KSU 模块）
   - Andrea-lyz/LKM-PathMask v2.8.3 的 4.14 Non-GKI 移植，保留原版
     service.sh、WebUI、配置项；内核态换成适配 4.14 的 `pathmask.ko`
   - 钩 `__inode_permission`、`vfs_getattr_nosec`、`SyS_getdents64`，
     并保留 stat/access/readlink 的 syscall fallback
   - 附带 `procguard.ko`（gid 3009 / AID_READPROC 隔离修复）
   - `.ko` 与内核同一次 CI 构建，vermagic/MODVERSIONS 必须配套使用
   - 用法：刷内核后安装 `A226B-PathMask-4.14-*.zip`，在它的 WebUI 里
     配置目标路径/UID

三、没有移植 / 已知限制
-----------------------
- priority UID filter（getpriority 滥用检测对抗）：上游 2026-10 才加入，
  Non-GKI 4.14 补丁尚未包含，本内核未启用。不影响其它隐藏功能。
- SELinux policy 深度隐藏（selinux_hide 的内核策略级部分）：4.14 的
  SELinux 内部结构差异过大，只保留了 avc 日志脱敏与 KSU 自身的 domain 处理。
- 由于以上两项缺失，SUSFS 的“全部功能”并非 100%，但路径/挂载/stat/maps/
  uname/cmdline/open_redirect/avc 日志等主力隐藏功能全部生效。
- 本内核已在 SM-A226B 实机验证：可正常开机，SUSFS 正常运作，NoMount
  可正常打开并生效（短期验证；长期稳定性仍以实测为准）。首次刷入前请
  务必备份原厂 boot.img，并确认已解锁 BootLoader。

四、构建
--------
GitHub Actions（推荐）：
  Actions -> Build SM-A226B kernel -> Run workflow
  产物：标准版 AnyKernel3 zip、KPM 版 AnyKernel3 zip、Image.gz / Image.kpm.gz、
        modules.zip、KPatch-Next-Module.zip

本地（Ubuntu 22.04+ / WSL2）：
  bash ci/fetch_toolchain.sh
  git clone https://github.com/Baka-SU/BakaSU.git KernelSU
  git clone https://github.com/maxsteeel/nomount.git NoMount
  bash ci/build.sh
  bash ci/package.sh
  bash ci/kpm_patch.sh      # 生成 Image.kpm / Image.kpm.gz
  bash ci/package_kpm.sh    # 生成 KPM 版 AnyKernel3 zip

工具链：AOSP clang-r383902 + GCC 4.9 binutils（Samsung 原厂同款）。
KPM：KPatch-Next 0.13.5-2 的 kptools/kpimg（脚本内固定版本）。

五、刷入
--------
1. 解锁 BootLoader（会清空数据并熔断 KNOX，不可逆）。
2. 在 TWRP 中二选一：
   - 普通使用：刷 A226B-BakaSU-SUSFS-NoMount-*.zip（标准版）
   - 需要 KPM：刷 A226B-BakaSU-SUSFS-NoMount-KPM-*.zip
3. 重启；首次开机较慢。
4. 安装 BakaSU 管理器 APK；再安装 NoMount 官方 Metamodule（可选）。
5. KPM 版还需要安装 Release 里的 KPatch-Next-Module-v0.0.1.zip，
   之后在它的 WebUI 里加载 `.kpm`；不要再用它的“patch boot”功能。
6. PathMask：安装 `A226B-PathMask-4.14-*.zip`（KSU 模块），重启后在它的
   WebUI 里配置 target_path / scope_mode；`.ko` 必须与本次内核配套。
7. 若无法开机：进 TWRP 恢复备份的 stock boot.img，或 Odin 刷回原厂 AP；
   KPM 版无法开机时先刷回标准版排除 KPM 因素。

注意：
- 本 zip 只替换 boot 分区中的 kernel，保留原厂 ramdisk/dtb。
- 标准版与 KPM 版是同一个内核源码，仅 Image 是否追加 kpimg 不同；
  两者不要混刷模块，KPM 版必须搭配 KPatch-Next-Module。
- 三星 AVB/vbmeta 可能导致校验失败；AK3 已带 PATCH_VBMETA_FLAG=auto，
  如仍无法开机请同时刷入 vbmeta_disabled（或使用已禁用校验的 TWRP）。
- KNOX 相关功能（Samsung Pay、Secure Folder 等）会永久失效。

六、目录说明
------------
- 内核源码根目录即本仓库根目录（完整 Samsung 4.14.186 + 集成修改）
- drivers/kernelsu -> ../KernelSU/kernel（构建时 clone，不入库）
- fs/nomount      -> ../NoMount/kernel/src（构建时 clone，不入库）
- ci/             构建脚本
- anykernel/      AnyKernel3 模板
- pathmask/       PathMask 4.14 移植源码 + KSU 模块外壳
- patches/        本仓库相对原厂源码的集成改动说明（见 patches/README.md）

七、维护、免费与自编译
----------------------
- **永久免费公开**：源码、CI 配置、Release 产物全部公开，不提供付费版、付费服务，
  也不要求任何授权码；欢迎 fork、自编译、二次分发。
- **持续维护**：BakaSU / NoMount 每次构建跟随上游最新 main/master；SUSFS 在上游
  更新后做 4.14 移植；PathMask 跟随上游 2.8.x；兼容性与安全问题通过 Issue 修复。
- **自行编译**：Fork 本仓库 → Actions → Build SM-A226B kernel → Run workflow；
  或按第四节在本地编译。产物在 Actions Artifacts，打 `v*` tag 会自动发 Release。
- **二次分发**：允许，但必须遵守 GPL-2.0 / GPL-3.0（见 [NOTICE.md](NOTICE.md)），
  保留来源与作者，不得把本项目包装成付费独家版本。
- **维护边界**：不承诺所有地区/固件版本都能开机；刷机风险自负；即使停止维护，
  全部源码与历史 Release 也会保留在仓库中。

八、致谢
--------
- BakaSU: https://github.com/Baka-SU/BakaSU
- SUSFS: simonpunk https://gitlab.com/simonpunk/susfs4ksu
- Non-GKI 4.14 SUSFS 移植: JackA1ltman
  https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd
- 4.14 Samsung 集成参考: betelqeyza
  https://github.com/betelqeyza/android_kernel_samsung_universal9611
- NoMount: maxsteeel https://github.com/maxsteeel/nomount
- PathMask: Andrea-lyz https://github.com/Andrea-lyz/LKM-PathMask
- AnyKernel3: osm0sis https://github.com/osm0sis/AnyKernel3

GPL-2.0，内核源码版权归 Samsung / 各原作者所有。
