> 🌐 **中文（默认）** | [English](en/MAINTAINER-NOTES.md)

# 接管者笔记 / Maintainer notes

> 写给"从零接手这个仓库的人或 AI"。这个仓库被完整开源的目的之一就是：
> 即使维护者换机器、丢本地文件，也能从仓库本身重建全部上下文。
> 阅读顺序建议：[README.md](../README.md) → 本文件 → [FEATURES.md](FEATURES.md) → [BUILD.md](BUILD.md) → [CHANGELOG.md](CHANGELOG.md)

## 0. 铁律：先有证据，再动内核

内核是不能靠猜的东西。下面每条都是踩过的坑换来的，改动前请逐条对照：

1. **没有证据就不改。** 任何改动之前必须拿到**可复现的证据**：`logcat`/`dmesg` 的具体行、
   字节级 diff、A/B 刷机对比，或能直接读出原因的 `/proc`、`/sys` 状态。
   拿不到证据时，只能记录"假设 + 如何验证"，不能直接动手。
2. **一次只改一个变量。** 多个改动叠在一起时，出问题无法归因。
   v1.4.0 的 `config.gz` 事故就是这么来的——七项加固一次上线，弹窗出现后只能回头逐项二分。
3. **每个改动都要先写清"期望看到什么"**：哪一行日志该消失、哪个哈希该相等、
   哪个文件该变成 `-r--r-----`。没有可判定的预期，就不算验证完成。
4. **假设被推翻时，要显式撤回。** 反面案例：开机弹窗最初被归因为"system/vendor 分区指纹
   混版"（听起来很合理，但它不成立）；真正原因是从 `framework-res.apk` 里取出资源名
   `system_error_manufacturer`、再回到 logcat 找到 `libvintf: Could not open /proc/config.gz`
   才定位的。沿着错误假设修下去只会引入更多风险。
5. **改动 userspace 可见行为前，先确认谁在读它。** 已知的真实依赖：

   | 文件/接口 | 读取者 | 收得太狠的后果 |
   |---|---|---|
   | `/proc/config.gz` | system_server 的 `libvintf`（VINTF 内核配置校验） | 开机弹「设备内部出现问题」（`system_error_manufacturer`） |
   | `/proc/version` | 多家检测库、部分三星组件 | 解析失败或行为异常 |
   | `dmesg_restrict` | `sec_debug`/bugreport 等特权服务 | 可能丢失启动诊断信息 |
   | `/proc/modules` | 检测器**和**部分 HAL 初始化逻辑 | 一致性问题（见 3.2 相关条目） |

6. **改完必须留回滚。** 刷机前备份 `boot` 分区并记录 sha256；仓库里保留原厂
   `boot-stock-backup.img` 的哈希，出问题能一条 `dd` 回滚。
7. **验证结论也要有证据。** 不要写"应该没问题"，要写"第 X 行日志已消失 / 哈希等于 Y /
   设备上第 N 项检查通过"。本仓库的验证记录都带具体值，就是为了可复核。

## 0.1 测试策略：默认用 KPM 版（功能超集）

**维护者自测与发布前验证，一律刷 KPM 版**（`A226B-BakaSU-SUSFS-NoMount-KPM-*.zip`）。

理由：KPM 版是标准版的**超集**——同一份内核源码，只是在镜像级追加并打补丁 kpimg。
刷一次就同时覆盖三件事：内核本体、SUSFS/NoMount/BakaSU/PathMask 全部功能、KPM 链路。
只测标准版永远测不到 KPM；测 KPM 版能把覆盖面拉到最大。

**边界（必须说清楚，不要当成"KPM 通过 = 标准版必然通过"）**：

- KPM 镜像 = 标准镜像经 kptools 打补丁 + 追加 kpimg，两者**不是**逐字节包含关系
  （实测 `sha256(kpm_Image[:len(Image)]) != sha256(Image)`），被补丁改写的指令区段
  在标准版里是原始代码
- 所以标准版的保证来自"同源码 + CI 逐字节产物一致"，而不是来自 KPM 版的实机结果；
  怀疑补丁区段有差异时，补刷一次标准版做对照

**KPM 版刷机后的验证清单**：

1. 读回 boot 分区内核段，`sha256` 必须等于 Release 里的 `Image.kpm.gz`
2. 7 项加固（见第 5 节）
3. `pathmask`/`procguard` 已加载、`boot_state=loaded`、隐藏目标生效
4. 安装 KPatch-Next-Module 后，用其 WebUI 能正常加载/卸载一个 `.kpm`
5. 无 `SYSTEM_ERROR` 窗口、无内核崩溃、`dmesg` 无告警

只刷内核而没装 KPatch-Next-Module 时，第 4 项无法验证，此时 KPM 部分只证明了
"打过补丁的内核能正常开机运行"。

## 0.2 KPM 链路的实测方法（可复现）

上面清单第 4 项"能加载一个 `.kpm`"可以用上游 demo 完整验证。本仓库的工具链只有 clang + binutils
（没有 gcc driver），所以不能直接 `make`，按下面两步编：

```bash
# 1) 编 demo（头文件来自 KPatch-Next 源码树，ci/kpm_patch.sh 已经把它下载到 .kpm-tools/）
KPSRC=~/a226b/.kpm-tools/KPatch-Next-0.13.5-2
CLANG=~/a226b/toolchain/clang/host/linux-x86/clang-r383902/bin/clang
LD=~/a226b/toolchain/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-androidkernel-ld
cd "$KPSRC/kpms/demo-hello"
INC=""; for d in . include patch/include linux/include linux/arch/arm64/include linux/tools/arch/arm64/include; do
    INC="$INC -I$KPSRC/kernel/$d"; done
$CLANG --target=aarch64-none-elf -ffreestanding -nostdlibinc -fno-builtin \
       $INC -Thello.lds -c -O2 -o hello.o hello.c
$LD -r -o hello.kpm hello.o          # 必须用 aarch64 的 ld，用宿主 ld 会报 EM:183 / wrong format
```

```sh
# 2) 设备上加载 → 调用 → 卸载（kpatch 在 /data/adb/modules/KPatch-Next/bin）
export PATH=/data/adb/modules/KPatch-Next/bin:$PATH
kpatch kpver                                  # 运行时版本，实测 d05
kpatch hello                                  # 期望 hello2026
kpatch kpm load /data/local/tmp/hello.kpm "args"   # rc=0
kpatch kpm list                               # kpm-hello-demo
kpatch kpm info kpm-hello-demo                # name/version/license/author
kpatch kpm ctl0 kpm-hello-demo ping123        # 期望回显 "echo: ping123"
kpatch kpm unload kpm-hello-demo              # rc=0
kpatch kpm num                                # 回到 0
```

期望的内核日志（`dmesg | grep -i kpm`）：

```
kpm hello init, event: load-file, args: ...
load_module: [kpm-hello-demo] succeed with [...]
kpm hello control0, args: ping123
kpm hello exit
unload_module: name: kpm-hello-demo, rc: 0
```

**实测结果（v1.4.0-fix / KPM 版）**：`kpver=d05`、`kver=40eba`、`hello=hello2026`，
load/ctl0/unload 全部 `rc=0`，`kpm num` 1 → 0，卸载后无崩溃、无 `SYSTEM_ERROR` 窗口。
这也证明发布包里的 `Image.kpm.gz` 不只是"多了 182 KB"——kpimg 真的接管并提供出了 KPM 运行时。

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

### 3.8 链接器 build-id：会让 Image 差 39 字节

所有输入钉死之后，本地与 CI 的 `Image` 仍会差 **39 字节**，集中在 vDSO 和内核各自的
`.note.gnu.build-id`。裸 `--build-id` 由链接器生成、值不稳定。
修法：`arch/arm64/kernel/vdso/Makefile` 改 `--build-id=none`，并在 `ci/build.sh` 里用
`LDFLAGS_BUILD_ID=` 覆盖 vmlinux/模块那两处。**除这 39 字节外内容本来就完全一致**，
所以只要看到"差的字节只有几十个且都在 `GNU\0` 之后"，就是这个原因。

### 3.9 模块的绝对路径：`.ko` 差 ~1.3 KiB

`make M=<绝对路径> modules` 会把绝对路径写进 `__FILE__` 与 DWARF 字符串
（CI 是 `/home/runner/work/...`，本地是 `/home/kali/...`），导致 `.rodata.str1.1`
和 `.debug_*` 尺寸不同。修法：`pathmask/build.sh` 里 `KCFLAGS="-ffile-prefix-map=$ROOT/="`。
**`ccflags-y` 里加无效**——覆盖不到生成的 `.mod.c`。

> `Image.gz` 的压缩字节还依赖宿主机 gzip 版本（CI 22.04 vs 本地 26.04 不同），
> 所以"产物一致"应以**解压后的 `Image`** 为准。

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
