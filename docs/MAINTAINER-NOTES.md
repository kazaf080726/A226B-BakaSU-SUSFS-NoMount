# 接管者笔记 / Maintainer notes

> 写给"从零接手这个仓库的人或 AI"。这个仓库被完整开源的目的之一就是：
> 即使维护者换机器、丢本地文件，也能从仓库本身重建全部上下文。
> 阅读顺序建议：[README.md](../README.md) → 本文件 → [FEATURES.md](FEATURES.md) → [BUILD.md](BUILD.md) → [CHANGELOG.md](CHANGELOG.md)

## 1. 这是什么

Samsung Galaxy A22 5G（SM-A226B / a22x，MT6833）的 **Linux 4.14.186** 内核，
在三星官方开源包基础上集成：

- **BakaSU**（KernelSU 分支，SUSFS Inline Hook 后端）
- **SUSFS v2.3.0**（4.14 Non-GKI 移植）
- **NoMount v2.2.0**（VFS 层路径重定向，编进内核）
- **PathMask 4.14**（`pathmask.ko` + `procguard.ko`，KSU 模块形式）
- 可选的 **KPM**（KPatch-Next 镜像级补丁）
- 一批**本项目自研的反检测加固**（见 FEATURES.md 第 6 节）

内核源码树就是仓库根目录；`drivers/kernelsu` 和 `fs/nomount` 是 **symlink**，
指向构建时 clone 的 `../KernelSU/kernel`、`../NoMount/kernel/src`（不入库）。

## 2. 接手第一步：确认基线是干净的

永远先做这件事，否则后面所有 diff 都不可信：

```bash
# 三星官方包 -> 解出 Kernel.tar.gz -> 与 baseline 提交逐文件比对
git archive cab987c8c | tar -x -C /tmp/base
tar -xzf Kernel.tar.gz -C /tmp/stock
( cd /tmp/base  && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/a
( cd /tmp/stock && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/b
diff /tmp/a /tmp/b
```

实测结论：**77,788 个文件 0 差异**（唯一多出来的是 3 个 DEFEX 生成物，
`security/samsung/defex_lsm/` 下的 `.bin`/`.inc`/`pack_rules`，原厂包不带）。

## 3. 非显然的坑（都踩过，别再踩）

### 3.1 `/proc/config.gz` 不能做成"仅 root 可读"

把 `kernel/configs.c` 的权限从 `0444` 改成 `0400` 会让**开机弹出**
「您的设备内部出现了问题。请联系您的设备制造商了解详情。」
（`android:string/system_error_manufacturer`，`TYPE_SYSTEM_ERROR` 窗口）。

原因链（实机 logcat 证据）：

```
libvintf: Could not open /proc/config.gz: 13            (EACCES)
libvintf: Cannot fetch or parse /proc/config.gz
VintfObject: verifyWithoutAvb() returns 1: ... No compatible kernel requirement found
VintfObject: For kernel requirements at matrix level 5, Missing config CONFIG_ADVISE_SYSCALLS
```

`system_server` 里的 `libvintf` 要读它校验内核配置与 framework 兼容性矩阵。
**正确做法**：`0440` + 属组 `system`(1000)，system 可读、App（uid≥10000）仍 `EACCES`。

### 3.2 `uname -r` 末尾的 `+` 不是脏树

`scripts/setlocalversion` 在 **`LOCALVERSION` 未设置** 且 HEAD 没有**附注标签**时无条件追加 `+`。
本仓库的 tag 都是轻量标签 → 恒定命中 → 版本串永远是 `4.14.186+`。
`ci/build.sh` 里 `export LOCALVERSION=`（允许外部覆盖）后稳定为 `4.14.186`。

### 3.3 `O=out` 构建会被源码树里残留的 generated 目录搞死

这棵三星树会把 `arch/arm64/include/generated`、`include/generated` 写进**源码树**。
`out/` 被清空而这两个目录还在时，kbuild 跳过为目标树重新生成，直接死在
`asm/types.h: file not found`。`ci/build.sh` 在"从零构建"时会先删掉它们；
手动构建请先 `rm -rf arch/arm64/include/generated include/generated`。

### 3.4 `.ko` 的 vermagic 必须与内核同批

`vermagic = 4.14.186 SMP preempt mod_unload modversions aarch64`，
内核 release 串一改（比如去掉 `+`），旧 `.ko` 就加载失败。
`ci/verify.sh` 会拦这个（不匹配直接让 CI 失败）。

### 3.5 构建元数据会进 Image

`linux_banner` 含 `<user>@<host>` 和 UTS 时间戳；内建 initramfs 的 cpio mtime 来自
`KBUILD_BUILD_TIMESTAMP`（`scripts/gen_initramfs_list.sh` 原生支持）。
所以 `ci/build.sh` 固定了 `KBUILD_BUILD_{USER,HOST,VERSION,TIMESTAMP}`，
时间戳取自受版本控制的 `ci/repro-date.txt`（不能用 `date`，也不能用提交时间）。

### 3.6 在 Windows 上 checkout 这个仓库会失真

- `drivers/.../aux.c`、`include/soc/arc/aux.h` 是 Windows 保留设备名，**建不出来**
- 12 组仅大小写不同的文件（`xt_MARK.h` vs `xt_mark.h`）会互相覆盖
- 38 个 symlink 会变成普通文本文件
- 系统级 `core.autocrlf=true` 会把整棵树转成 CRLF，编译直接崩

结论：**Linux 侧（WSL 原生路径）才是权威副本**；Windows 副本只用于编辑。

### 3.7 别在 `/mnt/d` 上跑 git

9p 文件系统上任何 `git status/diff` 都会对 7 万多个文件重新哈希，几分钟起步。
改动用"复制文件"同步，不要用 `git diff` 生成补丁（PowerShell 的 `>` 还会写成 UTF-16）。

## 4. 改动的边界

**已确认未被触碰**（相对原厂集成，`git diff` 为空）：
`fs/susfs.c`、`fs/namei.c`、`fs/readdir.c`、`fs/namespace.c`、`fs/stat.c`、`fs/statfs.c`、
`fs/exec.c`、`fs/open.c`、`fs/read_write.c`、`kernel/sys.c`、`kernel/reboot.c`、
`block/ioprio.c`、`security/selinux/{avc,hooks}.c`、`mm/memory.c`、`include/linux/susfs.h`、
`drivers/input/input.c`、`fs/proc/*`（除 `version.c`）等。

当前维护者新增/修改的内核文件仅 9 个，见 [FEATURES.md](FEATURES.md) 第 6 节。

## 5. 实机验证清单（7 项加固）

在一台已 root 的设备上（注意：如果 `adb shell` 本身就是 root，那么读到的权限
不能证明 App 侧行为，要看 `/proc/config.gz` 的 **mode**）：

```sh
cat /proc/version                       # 应跟随 SUSFS 伪造串，不含编译者
cat /proc/sys/kernel/osrelease          # 同伪造串，且不能是 4.14.186+
ls -l /proc/config.gz                   # -r--r----- root system
cat /proc/sys/kernel/dmesg_restrict      # 1
grep -c -E '(_ksu_|\.ksu_|susfs|kernelsu)' /proc/kallsyms   # 0
ls -l /sys/module/pathmask/parameters/  # 全部 -r--------
dumpsys window windows | grep -c ty=SYSTEM_ERROR            # 0
```

实测通过记录（v1.4.0-fix，`Image.gz = 0a02df04…`）：以上 7 项全部符合预期，
`pathmask`/`procguard` 均为 `Live`、`boot_state=loaded`、无内核告警。

## 6. 发版

```bash
git tag v1.x.y && git push origin main --tags
```

工作流会编译 → 跑 `ci/verify.sh` 门禁 → 上传 Artifacts → 自动创建 Release
（说明里自动带实际使用的 BakaSU/NoMount revision）。
注意：**两个内核包（标准版 / KPM 版）不要混刷模块**。
