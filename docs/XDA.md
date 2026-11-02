> 🌐 **中文（默认）** | [English](en/XDA.md)

# 发布帖草稿（中文）

> 用于国内论坛/酷安的发布或更新说明；英文版见 [docs/en/XDA.md](en/XDA.md)。
> 文中的 revision 与哈希以当次 Release 的 `build-info.txt` 为准，发帖前请核对。

---

## 【内核】【4.14.186】【A22 5G】SM-A226B (a22x) 的 BakaSU + SUSFS + NoMount —— 免费开源

**设备**：Samsung Galaxy A22 5G（SM-A226B / a22x，MediaTek MT6833）
**内核**：Linux 4.14.186，基于三星官方 `SM-A226B_13_Opensource` 开源包
**状态**：A226BZHSBDYA1（Android 13）实机验证通过，Root 与隐藏链路均正常

### 内含组件

- **BakaSU**（KernelSU 分支），使用 SUSFS 内联钩子后端
- **SUSFS v2.3.0** 下移到 4.14（Non-GKI）：sus_path、sus_mount、sus_kstat、
  uname/cmdline 伪造、open_redirect、sus_map、AVC 日志脱敏、符号隐藏
- **NoMount v2.2.0** 编进内核（VFS 层路径重定向，不产生真实挂载）
- **PathMask 4.14 移植**（`pathmask.ko` + `procguard.ko`），以 KernelSU 模块形式发布
- **可选 KPM 变体**：镜像级追加 KPatch-Next 的 kpimg，可加载 `.kpm` 模块
- **反检测加固**：在上游 SUSFS 之外补的七项（见下）
- **可复现构建**：同一提交 + 固定上游版本 = 逐字节一致的 `Image`

### 为什么还要给这台机器做内核

三星的 DEFEX 会拦截从 `/data` 执行 `su`/`ksud`，这是三星机型 KernelSU 拿不到 root 的常见原因。
本内核关闭 DEFEX（`CONFIG_SECURITY_DEFEX=n`），SELinux 仍保持 Enforcing。

### 反检测加固（实机以非 root 身份审计后逐项修复）

SUSFS 把路径、挂载、stat 都藏住了，但一个已 root 的内核仍然会"老实回答"一些很简单的问题：

| 探测点 | 加固前 | 加固后 |
|---|---|---|
| `/proc/version` | `4.14.186+ (A226B@a22x) ...` | 跟随 SUSFS 伪造的 uname |
| `/proc/sys/kernel/osrelease` | `4.14.186+`（与 uname 自相矛盾） | 跟随伪造 |
| `/proc/config.gz` | 全局可读，暴露 `CONFIG_KSU=y` | `0440` + 属组 system（App 不可读） |
| `dmesg` | 可读，含 `KernelSU:`/`susfs:` | `dmesg_restrict=1` |
| `/sys/module/pathmask/parameters/*` | 全局可读的隐藏路径配置 | root-only |
| `/proc/kallsyms` | 10 个含 `ksu`/`susfs` 的符号 | 已过滤 |
| `/proc/modules` | 列出 `pathmask`、`procguard` | 对 App UID 隐藏 |

> `/proc/config.gz` 没有做成"仅 root"是刻意的：system_server 的 `libvintf` 要用它做 VINTF
> 校验，收得太死会让开机弹出「设备内部出现问题」。

### 安装

1. 解锁 BootLoader（会清空数据并熔断 KNOX，不可逆）
2. **务必备份原厂 `boot.img`**，出问题可在 TWRP 或 Odin 里恢复
3. TWRP 刷 `A226B-BakaSU-SUSFS-NoMount-*.zip`；需要 KPM 才刷 `-KPM-` 版
4. 安装 KernelSU 兼容的管理器 APK；用 NoMount 的话再装它的 Metamodule
5. PathMask：刷**同一批构建**的 `A226B-PathMask-4.14-*.zip`——跨版本的 `.ko` 会 vermagic 不匹配

zip 只替换 boot 分区里的 kernel，原厂 ramdisk/DTB 保留；AnyKernel3 模板已带 `PATCH_VBMETA_FLAG=auto`。

### 已验证

- A226BZHSBDYA1 实机可正常开机；boot 分区 32 MiB、boot header v2、page size 2048
- `/proc/kallsyms` 中 susfs/ksu 符号 0 个；`uname` 已伪造为原厂串
- `pathmask`/`procguard` 已加载，`boot_state=loaded`
- 连续两次干净构建、CI 构建、Release 资产：8 个产物哈希完全一致
- 从设备读回 boot 分区，内核段 sha256 与发布的 `Image*.gz` 完全一致

### 已知限制

- SUSFS 的 priority-UID filter 与策略级 SELinux 隐藏未移植到 4.14
- `/sys/module/{pathmask,procguard}` 的目录名仍对 App 可见（参数值不可读）
- 标准版与 KPM 版不能混刷模块

### 致谢

BakaSU（Baka-SU）、SUSFS（simonpunk）、4.14 移植（JackA1ltman）、NoMount（maxsteeel）、
PathMask（Andrea-lyz）、KPatch-Next（KernelSU-Next）、AnyKernel3（osm0sis）、
以及提供内核源码的三星。

### 源码与构建

全部公开：内核源码、构建脚本、CI 配置、固定的上游 revision。可以 fork、跑工作流、自己编译——
没有付费版，也没有授权码。内核部分遵循 GPL-2.0，上游组件各自保留其许可证。

**刷机有风险，后果自负。解锁 BootLoader 后 KNOX 相关功能（Samsung Pay、Secure Folder）永久失效。**
