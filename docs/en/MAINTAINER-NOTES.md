> 🌐 **English** | [中文（默认）](../MAINTAINER-NOTES.md)

# Maintainer notes

> Written for whoever picks this repository up cold — a person or an AI. One of the reasons this project
> is fully open source is that even if the maintainer loses a machine or their local files, the whole
> context can be rebuilt from the repository itself.
> Suggested order: [README](../README.en.md) → this file → [FEATURES](FEATURES.md) → [BUILD](BUILD.md) → [CHANGELOG](CHANGELOG.md)

## 0. Ground rule: evidence before touching the kernel

A kernel is not something to guess about. Every rule below came from a bug that was actually hit in this
project — check them before changing anything:

1. **No change without evidence.** Before touching a file, have reproducible evidence in hand: a specific
   `logcat`/`dmesg` line, a byte-level diff, an A/B flash comparison, or a `/proc`/`/sys` value that
   states the cause directly. Without evidence, write down a hypothesis *and how to test it* — do not act.
2. **Change one variable at a time.** Several changes stacked together cannot be attributed when things
   break. The v1.4.0 `config.gz` incident happened exactly this way: seven hardening items landed at
   once, the boot dialog appeared, and the cause had to be bisected backwards.
3. **State the expected result before the change**: which log line should disappear, which hash should be
   equal, which file should become `-r--r-----`. No falsifiable expectation means no verification.
4. **Retract hypotheses explicitly when they are disproved.** Counter-example: the boot dialog was first
   blamed on "mixed system/vendor build fingerprints" (plausible-sounding, but wrong). The real cause was
   found by extracting the resource name `system_error_manufacturer` from `framework-res.apk` and then
   locating `libvintf: Could not open /proc/config.gz` in logcat. Continuing down the wrong path only adds
   risk.
5. **Check who reads an interface before narrowing it.** Known real dependencies:

   | File / interface | Reader | Consequence of over-restricting |
   |---|---|---|
   | `/proc/config.gz` | system_server's `libvintf` (VINTF kernel-config verification) | the framework shows a "device internal problem" dialog at boot (`system_error_manufacturer`) |
   | `/proc/version` | several detection libraries, some Samsung components | parse failures or odd behaviour |
   | `dmesg_restrict` | `sec_debug`/bugreport style privileged services | boot diagnostics may be lost |
   | `/proc/modules` | detectors **and** some HAL initialisation paths | consistency problems |

6. **Always leave a rollback.** Back up the `boot` partition and record its sha256 before flashing; the
   repository keeps the hash of the stock `boot-stock-backup.img` so one `dd` can undo a bad flash.
7. **Verification results need evidence too.** Never write "should be fine"; write "log line X is gone /
   hash equals Y / check N passed on the device". The verification records in this repository carry
   concrete values so they can be re-checked.

## 1. What this is

Samsung Galaxy A22 5G (SM-A226B / a22x, MT6833), **Linux 4.14.186**, built on Samsung's own open source
package with:

- **BakaSU** (a KernelSU fork with the SUSFS inline-hook backend)
- **SUSFS v2.3.0** (4.14 Non-GKI port)
- **NoMount v2.2.0** (VFS-level path redirection, compiled into the kernel)
- **PathMask 4.14** (`pathmask.ko` + `procguard.ko`, shipped as a KernelSU module)
- optional **KPM** (KPatch-Next image-level patch)
- the project's own **detection-leak hardening** (see FEATURES.md section 6)

The kernel source tree *is* the repository root; `drivers/kernelsu` and `fs/nomount` are **symlinks** to
`../KernelSU/kernel` and `../NoMount/kernel/src`, which are cloned at build time and not committed.

## 2. First step when taking over: prove the baseline is clean

Always do this first, otherwise no later diff can be trusted:

```bash
# unpack Kernel.tar.gz from Samsung's official zip and compare file by file with the baseline commit
git archive cab987c8c | tar -x -C /tmp/base
tar -xzf Kernel.tar.gz -C /tmp/stock
( cd /tmp/base  && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/a
( cd /tmp/stock && find . -type f -print0 | xargs -0 md5sum ) | sort -k2 > /tmp/b
diff /tmp/a /tmp/b
```

Measured: **77,788 files, 0 differences** (the only extras are three DEFEX build products —
`.bin`/`.inc`/`pack_rules` under `security/samsung/defex_lsm/` — which the official package does not ship).

## 3. Non-obvious traps (all of these were actually hit)

### 3.1 `/proc/config.gz` must not be made "root only"

Changing the mode in `kernel/configs.c` from `0444` to `0400` makes the device **show a dialog at boot**:
"您的设备内部出现了问题。请联系您的设备制造商了解详情。"
(`android:string/system_error_manufacturer`, a `TYPE_SYSTEM_ERROR` window).

The cause chain (logcat evidence from a real device):

```
libvintf: Could not open /proc/config.gz: 13            (EACCES)
libvintf: Cannot fetch or parse /proc/config.gz
VintfObject: verifyWithoutAvb() returns 1: ... No compatible kernel requirement found
VintfObject: For kernel requirements at matrix level 5, Missing config CONFIG_ADVISE_SYSCALLS
```

`libvintf` inside `system_server` reads this file to verify the kernel configuration against the framework
compatibility matrix. **Correct fix**: `0440` with group `system`(1000) — system can read it, apps
(uid ≥ 10000) still get `EACCES`.

### 3.2 The trailing `+` in `uname -r` is not a dirty tree

`scripts/setlocalversion` appends `+` unconditionally when **`LOCALVERSION` is unset** and HEAD has no
**annotated** tag. Every tag in this repository is lightweight, so the condition always matched and the
release string was permanently `4.14.186+`. `ci/build.sh` does `export LOCALVERSION=` (still
overridable), which pins it to `4.14.186`.

### 3.3 An `O=out` build dies because of leftover generated headers in the source tree

This Samsung tree writes `arch/arm64/include/generated` and `include/generated` into the **source tree**.
When `out/` has been wiped but those directories survive, kbuild skips regenerating them for the target
tree and dies on `asm/types.h: file not found`. `ci/build.sh` removes them for from-scratch builds; for
manual builds run `rm -rf arch/arm64/include/generated include/generated` first.

### 3.4 `.ko` vermagic must match the kernel build

`vermagic = 4.14.186 SMP preempt mod_unload modversions aarch64`. Change the kernel release string (for
example by dropping the `+`) and old `.ko` files stop loading. `ci/verify.sh` blocks this — a mismatch
fails CI.

### 3.5 Build metadata ends up inside the Image

`linux_banner` contains `<user>@<host>` and the UTS timestamp; the built-in initramfs takes its cpio
mtimes from `KBUILD_BUILD_TIMESTAMP` (`scripts/gen_initramfs_list.sh` supports it natively). `ci/build.sh`
therefore pins `KBUILD_BUILD_{USER,HOST,VERSION,TIMESTAMP}`, with the timestamp coming from the
version-controlled `ci/repro-date.txt` (never `date`, never the commit time).

### 3.6 Checking this repository out on Windows loses information

- `drivers/.../aux.c` and `include/soc/arc/aux.h` are reserved device names on Windows and **cannot be created**
- 12 pairs of files that differ only in case (`xt_MARK.h` vs `xt_mark.h`) overwrite each other
- 38 symlinks become ordinary text files
- a system-wide `core.autocrlf=true` converts the whole tree to CRLF and the build breaks immediately

Conclusion: **the Linux side (native WSL path) is the authoritative copy**; the Windows copy is for editing only.

### 3.7 Do not run git on `/mnt/d`

On 9p any `git status/diff` re-hashes 70k+ files and takes minutes. Synchronise edits by copying files, and
do not generate patches with `git diff` there (PowerShell's `>` also writes UTF-16).

### 3.8 Linker build-id: makes the Image differ by 39 bytes

With every input pinned, local and CI `Image` still differed by **39 bytes**, in the vDSO and kernel
`.note.gnu.build-id` notes. A bare `--build-id` is generated by the linker and is not stable.
Fix: `--build-id=none` in `arch/arm64/kernel/vdso/Makefile`, and `LDFLAGS_BUILD_ID=` on the command line
in `ci/build.sh` for vmlinux/modules. **Everything except those 39 bytes was already identical**, so "the
only differing bytes are a few dozen right after `GNU\0`" points straight at this.

### 3.9 Absolute paths in the modules: `.ko` differs by ~1.3 KiB

`make M=<absolute path> modules` writes the absolute path into `__FILE__` and the DWARF strings (CI:
`/home/runner/work/...`, local: `/home/kali/...`), which changes the size of `.rodata.str1.1` and the
`.debug_*` sections. Fix: `KCFLAGS="-ffile-prefix-map=$ROOT/="` in `pathmask/build.sh`.
**Adding it to `ccflags-y` does not work** — it never reaches the generated `.mod.c`.

### 3.10 The archives themselves

Zip stores local wall-clock time, follows readdir order and records entry mtimes; `gzip` writes name and
mtime into its header. All three are pinned now (`TZ=UTC`, sorted `zip -@`, `gzip -n`), and
`kernel/kheaders.ko` is no longer shipped because it archives whatever generated headers happen to exist
in the tree. Full table in [BUILD.md](BUILD.md) section 4.

> The compressed bytes of `Image.gz` also depend on the host gzip version (CI runs 22.04, the local
> machine 26.04), so "artifacts match" should be judged on the **decompressed `Image`**.

## 4. Boundaries of the changes

**Verified untouched** (relative to the upstream integration, `git diff` empty): `fs/susfs.c`,
`fs/namei.c`, `fs/readdir.c`, `fs/namespace.c`, `fs/stat.c`, `fs/statfs.c`, `fs/exec.c`, `fs/open.c`,
`fs/read_write.c`, `kernel/sys.c`, `kernel/reboot.c`, `block/ioprio.c`,
`security/selinux/{avc,hooks}.c`, `mm/memory.c`, `include/linux/susfs.h`, `drivers/input/input.c`,
`fs/proc/*` (except `version.c`), `drivers/kernelsu/`, `fs/nomount/`, `anykernel/`.

The current maintainer touches nine kernel/pathmask files in total, listed in
[FEATURES.md](FEATURES.md) section 6.

## 5. On-device verification checklist (the seven hardening items)

On a rooted device (note: if `adb shell` is already root, the modes you read do **not** prove app-side
behaviour — check the **mode** of `/proc/config.gz`):

```sh
cat /proc/version                       # follows the SUSFS spoof, no compiler identity
cat /proc/sys/kernel/osrelease          # same spoof, must not be 4.14.186+
ls -l /proc/config.gz                   # -r--r----- root system
cat /proc/sys/kernel/dmesg_restrict     # 1
grep -c -E '(_ksu_|\.ksu_|susfs|kernelsu)' /proc/kallsyms   # 0
ls -l /sys/module/pathmask/parameters/  # all -r--------
dumpsys window windows | grep -c ty=SYSTEM_ERROR            # 0
```

Measured on v1.4.0-fix (`Image.gz = 5e4f6ed7…`): all seven match, `pathmask`/`procguard` are `Live`,
`boot_state=loaded`, no kernel warnings.

## 6. Releasing

```bash
git tag v1.x.y && git push origin main --tags
```

The workflow builds, runs the `ci/verify.sh` gate, uploads artifacts and creates the release
automatically (the body lists the BakaSU/NoMount revisions actually used). Do not mix modules between the
standard and KPM builds.

## 7. Documentation language

Chinese is the default (`README.md`, `docs/*.md`). English mirrors live in `docs/en/` and `README.en.md`,
with a language switcher at the top of every file. When you change a document, change both sides and keep
the numbers identical — a stale hash in one language is worse than no hash at all.
