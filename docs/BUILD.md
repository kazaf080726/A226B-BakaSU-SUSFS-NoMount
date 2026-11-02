> 🌐 **中文（默认）** | [English](en/BUILD.md)

# 构建与可复现性 / Build & reproducibility

两条构建路径：GitHub Actions（推荐、可复现）和本地 WSL。

## 1. 依赖

Ubuntu 22.04 / 24.04 / 26.04 均可（CI 用 22.04，本地在 26.04 上验证通过）：

```bash
sudo apt-get update
sudo apt-get install -y build-essential bc bison flex libssl-dev libelf-dev lz4 \
    device-tree-compiler python3 zip unzip cpio rsync curl git zlib1g-dev
```

工具链不需要手动装：`ci/fetch_toolchain.sh` 会下载三星原厂同款的
**AOSP clang-r383902** 和 **GCC 4.9 binutils**（约 330 MB）到 `toolchain/`。
顶层 `Makefile` 里 `CC` 的路径是**硬编码**的，所以工具链必须放在这个位置。

## 2. 固定上游版本

内核源码树里没有 KernelSU / NoMount 源码，它们通过 symlink 引入、构建时 clone：

```
drivers/kernelsu -> ../KernelSU/kernel
fs/nomount      -> ../NoMount/kernel/src
```

两个版本**固定**在 `.github/workflows/build.yml` 的 `BAKASU_REF` / `NOMOUNT_REF`：

```
BAKASU_REF  = 516d3e87fbc986ccefdde2c2765f1700612441a9   (v4.2.0-rc3-86-g516d3e87)
NOMOUNT_REF = bf1847f98fed382369c43bfd652cd93774b9b8e3   (v2.2.0)
```

升级上游：改这两个值 → 跑一次全链路 → 确认能开机 → 提交。
临时试新版可以走 `workflow_dispatch` 的 `bakasu_ref` / `nomount_ref` 输入，不必改文件。

## 3. 本地构建（WSL）

```bash
git clone https://github.com/kazaf080726/A226B-BakaSU-SUSFS-NoMount.git a226b
cd a226b
bash ci/fetch_toolchain.sh
git clone https://github.com/Baka-SU/BakaSU.git KernelSU
git -C KernelSU checkout "$(grep -oP 'BAKASU_REF: \K\w+' .github/workflows/build.yml)"
git clone https://github.com/maxsteeel/nomount.git NoMount
git -C NoMount checkout "$(grep -oP 'NOMOUNT_REF: \K\w+' .github/workflows/build.yml)"

bash ci/build.sh        # -> out/arch/arm64/boot/Image, Image.gz
bash ci/package.sh      # -> dist/A226B-BakaSU-SUSFS-NoMount-<date>.zip
bash pathmask/build.sh  # -> dist/A226B-PathMask-4.14-<date>.zip（必须在 build.sh 之后）
bash ci/kpm_patch.sh    # -> Image.kpm / Image.kpm.gz
bash ci/package_kpm.sh  # -> KPM 版 zip
```

`JOBS=n` 控制并行度，`OUT=...` 换输出目录。

## 4. 可复现构建

`ci/build.sh` 默认 `REPRO=1`，把四个会让产物飘的输入全部钉死：

| 变量 | 来源 | 为什么必须固定 |
|---|---|---|
| `KBUILD_BUILD_USER` | `A226B` | 进 `linux_banner` |
| `KBUILD_BUILD_HOST` | `a22x` | 进 `linux_banner` |
| `KBUILD_BUILD_VERSION` | `1` | 进 `UTS_VERSION` |
| `KBUILD_BUILD_TIMESTAMP` | `ci/repro-date.txt` 第一行 | 进 banner **和** 内建 initramfs 的 cpio mtime（`scripts/gen_initramfs_list.sh` 原生支持） |

时间戳取的是**受版本控制的一行文本**，不是 `date` 也不是提交时间——否则"提交前本地构建"和"CI 构建 pushed commit"
会因为时间不同而字节不同。发版时把 `ci/repro-date.txt` 改成发版日期即可。

另一个容易踩的点：`scripts/setlocalversion` 在 `LOCALVERSION` **未设置**、且 HEAD 没有**附注标签**时，
会无条件给版本串追加 `"+"`（本仓库用的是轻量标签，所以永远命中，`uname -r` 一直是 `4.14.186+`）。
这会让版本串取决于 git 状态，本地和 CI 永远差一个字符。`ci/build.sh` 因此显式 `export LOCALVERSION=`（允许外部覆盖），
版本串稳定为 `4.14.186`。

再加上固定的工具链（`clang-r383902` + `binutils 2.27`），本地与 CI 的输入完全一致。

### 还有两个只在"本地 vs CI"之间才暴露的坑

**① 链接器 build-id（Image 差 39 字节）**

所有输入都钉死后，本地和 CI 的 `Image` 仍然会差 **39 字节**，且集中在两处：
vDSO 里的 `.note.gnu.build-id`（19 字节）和内核自身的同名 note（20 字节）。
`GNU ld` 对裸 `--build-id` 生成的值不稳定，而 kbuild 默认会加：

```make
# Makefile:972
LDFLAGS_BUILD_ID := ... (--build-id)
KBUILD_LDFLAGS_MODULE += $(LDFLAGS_BUILD_ID)
LDFLAGS_vmlinux += $(LDFLAGS_BUILD_ID)
# arch/arm64/kernel/vdso/Makefile:16 里还显式写了 --build-id
```

修法：vDSO 那处改成 `--build-id=none`，vmlinux/模块通过命令行覆盖 `LDFLAGS_BUILD_ID=`。
修完之后逐字节比对：其余 29,894,653 字节本来就完全一致。

**② 模块里的绝对路径（`.ko` 差 ~1.3 KiB）**

`pathmask`/`procguard` 是用 `make M=<绝对路径> modules` 编的，所以 `__FILE__`
和 DWARF 字符串里带的是绝对路径：CI 是 `/home/runner/work/.../pathmask/src/pm_main.c`，
本地是 `/home/kali/a226b/pathmask/src/pm_main.c`，长度不同 → `.rodata.str1.1`
和 `.debug_*` 差出 1KB 多。

修法：`pathmask/build.sh` 里给 `KCFLAGS` 加 `-ffile-prefix-map=$ROOT/=`。
注意 **`ccflags-y` 里加这个不起作用**（覆盖不到生成的 `.mod.c`），必须走 `KCFLAGS`。

### 实测结果

同一棵树、两次 `rm -rf out` 全量构建，间隔约 10 分钟：

```
Image    : 2ba7cd790a54e0e1acbc50ed5bd762892a956ba8bc7442c9d924567ef9f90645   (两次一致)
Image.gz : 5e4f6ed75d05a2862c090f65c4579f1c3d17050dca10b5d94db0e96d9553f05d   (两次一致)
```

跨主机验证：同一份源码在 GitHub Actions 上也得到同样的两个哈希；v1.4.0 Release 里的
8 个资产下载回来逐个比对，**8/8 逐字节一致**。

> `Image.gz` 的**压缩字节**还取决于宿主机 gzip 版本（CI 的 Ubuntu 22.04 与本地 26.04 不同），
> 所以严格比对时请比较**解压后的 `Image`**：`ci/verify.sh` 的复现检查也是基于它。

### ③ zip 包本身：时间戳、gzip 头、DWARF

镜像一致之后，**发布包**（zip）仍然会每次不同，三个原因都已消除：

| 来源 | 现象 | 修法 |
|---|---|---|
| `STAMP=$(date -u +%Y%m%d)` | 文件名随构建日期变 | 改为从 `ci/repro-date.txt` 推导 |
| `build-info.txt` 里的 `date:` | 每次构建时间不同 | 改用同一个 `BUILD_TS` |
| zip 内各条目的 mtime | 打包瞬间的时钟 | `touch -d "$BUILD_TS"` 全部归一 + `zip -X`（去掉扩展时间戳字段） |
| `gzip` 头里的文件名/mtime | `Image.kpm.gz` 每次都变 | `gzip -9 -n`（`-n` 即 kbuild 用的那个开关） |
| `.ko` 里的 DWARF | 头文件搜索路径编码不同 | 打包前 `strip --strip-debug`（顺带把 270 KB 降到 48 KB） |
| zip 条目顺序 | 跟随 readdir 顺序，不同主机不同 | `find ... -printf '%P' \| LC_ALL=C sort \| zip -@` |
| zip 里的时间戳 | zip 存的是**本地墙钟**，UTC runner 与 UTC+8 主机差 8 小时 | 打包全程 `TZ=UTC` |
| `kernel/kheaders.ko` | 把全部头文件打包，cpio 保留了 checkout 时的 mtime，tar 又按 readdir 顺序 | `kernel/gen_kheaders.sh`：`touch -d "$KBUILD_BUILD_TIMESTAMP"` + `tar --sort=name --mtime=... --numeric-owner`；**该模块不随包发布**（见下） |

> `kernel/kheaders.ko` 另外还有一个无法消除的主机差异：它会把源码树里 **已经生成出来的** 头文件一起打包，
> 全新 clone 的 CI 一个都没有，而在原地构建过的树会有 17 个（`arch/arm64/include/generated/*`），
> 归档大小因此差约 26 KB。这个模块只是 `ikheaders` 调试设施（运行时读内核头文件），
> 手机上没有任何用途，`.ko` 有 3.3 MB，所以 `ci/package.sh` **不再把它打进 modules 包**。

实测：连续两次完整打包，**8 个产物哈希全部相同**（4 个 zip + Image.gz + Image.kpm.gz + 2 个 .ko）。

## 5. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `asm/types.h: file not found`（`kernel/bounds.s`） | 源码树里残留了 `arch/arm64/include/generated`、`include/generated`，kbuild 会跳过为目标树重新生成。`ci/build.sh` 在从零构建时会自动清掉；手动构建可先 `rm -rf arch/arm64/include/generated include/generated` |
| `uname -r` 带 `+` | 旧行为：`LOCALVERSION` 未设置且没有附注标签时 `scripts/setlocalversion` 会加 `+`。`ci/build.sh` 现已固定 `LOCALVERSION=`，版本串为 `4.14.186` |
| `Image` 比 boot 分区大 | a22x 的 boot 分区 32 MiB；AK3 会用 `Image.gz`（约 12 MiB），不要直接塞未压缩的 `Image`（约 29 MiB） |
| `kptools` 报 GLIBC 版本 | 官方 release 二进制要求更高 glibc；`ci/kpm_patch.sh` 已改为从源码编译 |
| `pathmask.ko` insmod 失败 / vermagic 不符 | `.ko` 必须与内核同一次构建产出，不能跨版本混用 |
| 在 WSL 里操作 `/mnt/d` 上的仓库极慢 | 9p 文件系统会让 git 全库重哈希；把仓库放在 WSL 原生路径（如 `~/a226b`） |

## 6. 发布流程

```bash
git tag v1.4.0
git push origin main --tags
```

tag push 会触发 Actions：编译 → 打包 → 上传 Artifacts → 自动创建 Release。
Release 说明由 `dist/release-body.md` 生成，会自动带上本次实际使用的
BakaSU / NoMount revision 和 KPatch-Next 版本。
