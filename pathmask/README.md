# PathMask 4.14 移植说明

本目录是 [Andrea-lyz/LKM-PathMask](https://github.com/Andrea-lyz/LKM-PathMask)
v2.8.3 的 4.14 Non-GKI 移植，保留其 KernelSU 模块外壳（service.sh、WebUI、
配置项），只替换内核态 `.ko`。

## 改了什么

原版是 GKI 5.10+ 的 DDK/KMI 模块，依赖 KMSDK + KallRecon 从 stripped Image
里恢复 kallsyms，并钩 `__arm64_sys_*` 等 5.10+ 才有的入口。4.14 的差异处理：

1. **去掉 KallRecon/KMSDK 依赖**
   - 4.14 的 `kallsyms_lookup_name`、`kern_path`、`path_put` 都是导出符号，
     直接使用，不再扫描 kallsyms 表。
2. **hook 点下沉到 4.14 的真实函数**
   - `inode_permission` 在 4.14 只是薄包装，内部走 `__inode_permission`；
     改钩 `__inode_permission`。
   - `vfs_getattr` 内部走 `vfs_getattr_nosec`；改钩 `vfs_getattr_nosec`。
   - `SyS_getdents64` 替代 `__arm64_sys_getdents64`。
3. **syscall fallback 前缀适配**
   - `__arm64_sys_*` → `SyS_*`；`faccessat2`/`openat2` 在 4.14 不存在，
     注册失败会自动跳过；`openat` 因缺少 `close_fd` 在注册阶段跳过，
     避免 fd 泄漏。
   - 4.14 没有 ThinLTO，`__inode_permission` / `vfs_getattr_nosec` 不会被
     内联掉，所以主隐藏路径不依赖 syscall hook。
4. **少量 4.14 API 兼容**
   - 补 `regs_set_return_value`（arm64 `regs->regs[0]`）。
   - 补 `<linux/ratelimit.h>`。
5. **procguard 同步移植**：只依赖 `in_group_p` kretprobe，直接可用。

## 保留的功能

- `target_paths` / `target_path` 路径隐藏
- `scope_mode=global/deny/allow`、`deny_uids`、`hide_isolated`
- `hide_dirents`（getdents64 过滤）
- `write_op_policy`（passthrough/eacces/enoent）
- `procguard.ko`（gid 3009 / AID_READPROC 隔离进程修复）
- 原版 KernelSU 模块：持久化配置、WebUI、热重载、诊断

## 限制

- 4.14 无 `faccessat2`/`openat2`；这两个 syscall hook 不会注册。
- `openat` hook 因 `close_fd` 不可用而跳过；open 的隐藏依赖
  `__inode_permission`，在无 LTO 的 4.14 上可用。
- 模块 vermagic 必须与内核完全一致，因此 `.ko` 与内核同一次 CI 构建产出，
  不要跨版本混用。
- PathMask 与 SUSFS/NoMount 都会改 VFS 可见性；同时开启同一路径的隐藏
  属于叠加使用，未做专项组合测试。
