> 🌐 **中文（默认）** | [English](en/RELEASE-v1.4.0.md)

# v1.4.0 — 可复现构建 + 反检测加固

> 本文件是 **v1.4.0 的发布说明草稿**，可用于打 tag 时的附注说明，或在工作流自动生成
> 的 Release 说明之外补充背景。实际 revision 与哈希以每次构建的 `build-info.txt` 为准。

## 中文

**内核**：Linux 4.14.186（三星 SM-A226B 官方开源包，基线逐字节校验）
**组件**：BakaSU `516d3e87`、SUSFS `v2.3.0`（4.14 Non-GKI 移植）、NoMount `bf1847f`、
KPatch-Next `0.13.5-2`、PathMask 2.8.x（4.14 移植）

### 本版重点

1. **可复现构建**
   同一个提交、同一套固定依赖与工具链，本地与 CI 产出的 `Image`/`Image.gz`
   逐字节一致。两个会漂移的输入已钉死：
   - 构建元数据（`KBUILD_BUILD_USER/HOST/VERSION` + 受版本控制的 `ci/repro-date.txt`）
   - 版本串后缀（`LOCALVERSION=` 消除 `setlocalversion` 无条件追加的 `+`）

2. **上游版本固定**
   此前每次构建都拉 BakaSU `main`，两天内实际漂移过 `d5e9e02` → `5785bdb8` → `516d3e87`，
   同一个 tag 重新构建会得到不同内核。现在固定在 workflow 的 `BAKASU_REF`/`NOMOUNT_REF`，
   需要升级时改这两行或手动运行工作流并填 `bakasu_ref`/`nomount_ref`。

3. **反检测加固（7 项）**
   在真机上以非 root 身份逐项探测后修复了四处"全局可读"的泄漏，并收敛了两处符号泄漏：
   - `/proc/version` 跟随 SUSFS 伪造的 `uname`
   - `/proc/sys/kernel/{osrelease,version}` 同样跟随伪造（此前与 `uname` 直接矛盾）
   - `/proc/config.gz` 改为 `0440` + 属组 `system`(1000)（`libvintf` 必须能读）
   - `dmesg_restrict` 默认 1
   - `/sys/module/{pathmask,procguard}/parameters/*` 改为 root-only
   - `/proc/kallsyms` 覆盖全部 10 个残留的 ksu 符号
   - `/proc/modules` 对 app UID 隐藏 `pathmask`/`procguard`

### 本版资产（已验证，逐字节）

Release：https://github.com/kazaf080726/A226B-BakaSU-SUSFS-NoMount/releases/tag/v1.4.0

本地构建、CI 构建、Release 资产三方**逐字节一致**（8/8）：

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

### 刷入

1. 备份原厂 `boot.img`（务必）
2. TWRP 刷 `A226B-BakaSU-SUSFS-NoMount-*.zip`（标准版）；需要 KPM 则刷 `-KPM-` 版
3. PathMask 用户：同时刷本版配套的 `A226B-PathMask-4.14-*.zip`（`.ko` 的 vermagic 必须与内核同批）
4. 首启较慢属正常

### 已知限制

- `/proc/sys/kernel/*` 的伪造依赖 SUSFS 的 spoof_uname 已生效（susfs4ksu 模块需开启）
- `/sys/module/{pathmask,procguard}` 的**目录名**仍对 App 可见（参数已不可读）
- SUSFS 的 priority UID filter 与 SELinux 策略级隐藏仍未移植（见 docs/FEATURES.md 第 9 节）

## English

**Kernel**: Linux 4.14.186 (Samsung SM-A226B open source, baseline byte-verified)
**Components**: BakaSU `516d3e87`, SUSFS `v2.3.0` (4.14 non-GKI port), NoMount `bf1847f`,
KPatch-Next `0.13.5-2`, PathMask 2.8.x (4.14 port)

### Highlights

1. **Reproducible builds** — the same commit with the pinned dependencies and toolchain
   produces a byte-identical `Image`/`Image.gz` locally and on CI. Two sources of drift are
   pinned: the build metadata (`KBUILD_BUILD_*`, timestamp from a version-controlled file)
   and the release-string suffix (`LOCALVERSION=` suppresses the unconditional `+`).
2. **Pinned upstream revisions** — BakaSU `main` is no longer pulled at build time
   (it moved three times in two days, which silently changed the kernel behind a fixed tag).
3. **Detection-leak hardening (7 items)** — `/proc/version`, `/proc/sys/kernel/{osrelease,version}`,
   `/proc/config.gz`, `dmesg`, `/sys/module/*/parameters/*`, `/proc/kallsyms` and
   `/proc/modules` no longer hand a rooted-kernel fingerprint to unprivileged apps.

### Flashing

1. Back up your stock `boot.img` first.
2. Flash `A226B-BakaSU-SUSFS-NoMount-*.zip` in TWRP (or the `-KPM-` variant if you need KPM).
3. PathMask users: flash the matching `A226B-PathMask-4.14-*.zip` from the same build.
4. First boot takes a while.

### Known limitations

- The `/proc/sys/kernel/*` spoofing needs SUSFS `spoof_uname` to be active (susfs4ksu module).
- `/sys/module/{pathmask,procguard}` directory names stay visible to apps (values are not).
- SUSFS priority-UID filter and policy-level SELinux hiding are still not ported.
