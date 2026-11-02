# 变更历史 / Changelog

按版本倒序。逐条细节见 `git log`；功能与生效点见 [FEATURES.md](FEATURES.md)。

## 未发布 — v1.4.0

### 构建可复现
- 固定 `KBUILD_BUILD_{USER,HOST,VERSION}`，`KBUILD_BUILD_TIMESTAMP` 取自受版本控制的
  `ci/repro-date.txt`（不用时钟、不用提交时间，否则"提交前构建"和 CI 构建必然不同）
- 固定 `LOCALVERSION=`：`scripts/setlocalversion` 在无附注标签时会无条件追加 `+`，
  此前 `uname -r` 永远是 `4.14.186+`；现在稳定为 `4.14.186`
- 实测：同一棵树两次 `rm -rf out` 全量构建，`Image` / `Image.gz` 逐字节一致
- 从零构建前清理源码树里残留的 `arch/*/include/generated`、`include/generated`，
  否则 `O=out` 构建会跳过重新生成并死在 `asm/types.h: file not found`
- 删除误提交的 kbuild 主机产物（`scripts/basic/fixdep`、`bin2c`、`scripts/unifdef`、
  `scripts/.*.cmd`、`pathmask/src/.tmp_versions/*.mod`）——它们在每次构建后被重写，
  让工作树变脏
- 文件模式：`README.md`、`NOTICE.md`、`.gitignore`、workflow、`patches/README.md`、
  `pathmask/README.md` 由 755 改回 644

### CI / 发布
- 固定上游版本：`BAKASU_REF` = `516d3e87…`、`NOMOUNT_REF` = `bf1847f…`
  （此前每次构建拉 `main`，两天内实际漂移了 `d5e9e02` → `5785bdb8` → `516d3e87`）
- Release 资产补上 `dist/*.ko`
- Release 说明改为从 `build-info.txt` 自动生成，含实际使用的 revision（此前手写的
  "Actual build in these assets" 备注会被 `overwrite: true` 抹掉）

### 反检测加固（实机审计驱动）
- `/proc/version` 跟随 SUSFS 伪造的 `uname`（此前直接暴露 `4.14.186+ (A226B@a22x)`）
- `/proc/sys/kernel/{osrelease,version}` 同样跟随伪造（此前与 `uname` **自相矛盾**）
- `/proc/config.gz` 由 `0444` 改为 `0400`（此前可直接读出 `CONFIG_KSU=y` 等）
- `CONFIG_SECURITY_DMESG_RESTRICT=y`（此前 `dmesg_restrict=0`，dmesg 里有 `KernelSU:`/`susfs:`）
- `/sys/module/{pathmask,procguard}/parameters/*` 由 `0644/0444` 改为 `0400`
  （此前能读到 `target_paths`、`deny_uids` 等隐藏配置）
- `/proc/kallsyms` 增加 `_ksu_` / `.ksu_` / `susfs` / `kernelsu` / `ksud` 子串过滤，
  覆盖设备上残留的全部 10 个符号（含 `__initcall_kernelsu_init6`）
- `/proc/modules` 对 app/isolated UID 隐藏 `pathmask`、`procguard`

### 文档
- 新增 [FEATURES.md](FEATURES.md)：逐项功能 → 生效文件/行号 → 验证方法
- 新增 [BUILD.md](BUILD.md)：CI 与本地两条路径、可复现原理、常见报错对照
- 新增本 CHANGELOG 与 [RELEASE-v1.4.0.md](RELEASE-v1.4.0.md)（发版说明草稿）

## v1.3.1 — 2026-10-31

- `pathmask`: 4.14 syscall ABI 修正（`regs->regs[2]` 取代 5.x 的 `user_regs->regs[2]`）
- `pathmask`: getdents 缓冲改为 `GFP_ATOMIC` 并限制 16 KiB（kretprobe 里 `GFP_KERNEL` 会让
  SEC_DEBUG panic 重启）
- `ksu`: `getpriority`/`setpriority`/`ioprio_*` 隐藏 app/isolated UID 枚举
- `procfs`: `/proc/fs` 改为 root-only（对抗通过 `/proc/fs/jbd2`、`/proc/fs/ext4` 判定
  loop 挂载 ext4 镜像的检测）

## v1.2.0 — 2026-10-30

- 新增 PathMask 4.14 移植：`pathmask.ko` + `procguard.ko`，保留上游 KSU 模块外壳
  （service.sh、WebUI、全部配置项）
- CI 增加 LKM 构建与 `A226B-PathMask-4.14-*.zip` 上传
- `.gitignore` 补 pathmask 编译产物

## v1.1.0 — 2026-10-30

- 新增 KPM 变体：KPatch-Next `0.13.5-2` 的 kpimg 镜像级追加（不改内核源码）
- `kptools` 改为从源码编译（官方 release 二进制要求高于 ubuntu-22.04 的 glibc）
- Release 同时提供标准版与 KPM 版 zip

## v1.0.1 — 2026-10-29

- AnyKernel3 的 boot 分区路径修正为 `/dev/block/by-name/boot`

## 初始集成（无 tag） — 2026-10-29

- 三星 `SM-A226B_13_Opensource` 的 4.14.186 原厂源码作为基线（与官方包逐字节一致）
- 集成 BakaSU（SUSFS Inline Hook）、SUSFS v2.3.0 的 4.14 Non-GKI 移植、NoMount v2.2.0
- 关闭 `CONFIG_SECURITY_DEFEX`
- AnyKernel3 打包、GitHub Actions 构建
