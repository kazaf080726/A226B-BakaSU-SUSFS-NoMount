> 🌐 **English** | [中文（默认）](../BUILD.md)

# Build & reproducibility

Two build paths: GitHub Actions (recommended, reproducible) and a local WSL build.

## 1. Dependencies

Ubuntu 22.04 / 24.04 / 26.04 all work (CI uses 22.04, local verification was done on 26.04):

```bash
sudo apt-get update
sudo apt-get install -y build-essential bc bison flex libssl-dev libelf-dev lz4 \
    device-tree-compiler python3 zip unzip cpio rsync curl git zlib1g-dev
```

The toolchain is fetched automatically: `ci/fetch_toolchain.sh` downloads the **AOSP clang-r383902** and
**GCC 4.9 binutils** pair Samsung used (~330 MB) into `toolchain/`. The top-level `Makefile` hardcodes
the `CC` path, so the toolchain must live in exactly that location.

## 2. Pinned upstream revisions

The kernel source tree does not contain KernelSU / NoMount; they are pulled in through symlinks and
cloned at build time:

```
drivers/kernelsu -> ../KernelSU/kernel
fs/nomount      -> ../NoMount/kernel/src
```

Both revisions are **pinned** in `.github/workflows/build.yml` through `BAKASU_REF` / `NOMOUNT_REF`:

```
BAKASU_REF  = 516d3e87fbc986ccefdde2c2765f1700612441a9   (v4.2.0-rc3-86-g516d3e87)
NOMOUNT_REF = bf1847f98fed382369c43bfd652cd93774b9b8e3   (v2.2.0)
```

To upgrade: change the two values, run the full pipeline, confirm the device boots, commit.
To try a newer revision temporarily, use the `bakasu_ref` / `nomount_ref` inputs of `workflow_dispatch`
instead of editing files.

## 3. Local build (WSL)

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
bash pathmask/build.sh  # -> dist/A226B-PathMask-4.14-<date>.zip (must run after build.sh)
bash ci/kpm_patch.sh    # -> Image.kpm / Image.kpm.gz
bash ci/package_kpm.sh  # -> KPM zip
```

`JOBS=n` controls parallelism, `OUT=...` changes the output directory.

## 4. Reproducible builds

`ci/build.sh` defaults to `REPRO=1` and pins the four inputs that would otherwise drift:

| Variable | Source | Why it must be pinned |
|---|---|---|
| `KBUILD_BUILD_USER` | `A226B` | ends up in `linux_banner` |
| `KBUILD_BUILD_HOST` | `a22x` | ends up in `linux_banner` |
| `KBUILD_BUILD_VERSION` | `1` | ends up in `UTS_VERSION` |
| `KBUILD_BUILD_TIMESTAMP` | first line of `ci/repro-date.txt` | ends up in the banner **and** in the cpio mtimes of the built-in initramfs (`scripts/gen_initramfs_list.sh` honours it natively) |

The timestamp is a **version-controlled line of text**, not `date` and not the commit time. Otherwise a
build made before committing and a CI build of the pushed commit would differ purely by clock. Bump
`ci/repro-date.txt` when releasing.

Another easy trap: `scripts/setlocalversion` appends `"+"` whenever `LOCALVERSION` is **unset** and HEAD
carries no **annotated** tag (this repository uses lightweight tags, so it always matched and `uname -r`
was forever `4.14.186+`). That made the release string depend on git state and local/CI could never
agree. `ci/build.sh` therefore does `export LOCALVERSION=` explicitly (still overridable), keeping the
release string at `4.14.186`.

Together with the pinned toolchain (`clang-r383902` + `binutils 2.27`) the inputs of a local and a CI
build are identical.

### Two more traps that only show up when comparing local against CI

**1) Linker build-id (Image differs by 39 bytes)**

With every other input pinned, the local and CI `Image` still differed by **39 bytes**, in exactly two
places: the vDSO `.note.gnu.build-id` (19 bytes) and the kernel's own note (20 bytes). `GNU ld` produces
an unstable value for a bare `--build-id`, and kbuild adds it by default:

```make
# Makefile:972
LDFLAGS_BUILD_ID := ... (--build-id)
KBUILD_LDFLAGS_MODULE += $(LDFLAGS_BUILD_ID)
LDFLAGS_vmlinux += $(LDFLAGS_BUILD_ID)
# arch/arm64/kernel/vdso/Makefile:16 also spells out --build-id
```

Fix: use `--build-id=none` for the vDSO and override `LDFLAGS_BUILD_ID=` on the command line for
vmlinux/modules. After that, a byte comparison shows the remaining 29,894,653 bytes were already identical.

**2) Absolute paths inside the modules (`.ko` differs by ~1.3 KiB)**

`pathmask`/`procguard` are built with `make M=<absolute path> modules`, so `__FILE__` and the DWARF
strings contain absolute paths: CI writes `/home/runner/work/.../pathmask/src/pm_main.c`, a local build
writes `/home/kali/a226b/pathmask/src/pm_main.c`, and the different length shifts `.rodata.str1.1` and
`.debug_*` by more than 1 KiB.

Fix: pass `KCFLAGS=-ffile-prefix-map=$ROOT/=` in `pathmask/build.sh`. Note that adding it to
**`ccflags-y` does not work** (it does not reach the generated `.mod.c`); it has to go through `KCFLAGS`.

### Measured results

Two full builds (`rm -rf out` each time) of the same tree, ten minutes apart:

```
Image    : 2ba7cd790a54e0e1acbc50ed5bd762892a956ba8bc7442c9d924567ef9f90645   (identical)
Image.gz : 5e4f6ed75d05a2862c090f65c4579f1c3d17050dca10b5d94db0e96d9553f05d   (identical)
```

Cross-host check: the same two hashes came out of a GitHub Actions runner, and the resulting artifacts
were downloaded from the v1.4.0 release and compared file by file — 8/8 identical.

> The **compressed bytes** of `Image.gz` also depend on the host gzip version (CI runs Ubuntu 22.04, the
> local machine 26.04), so strict comparisons should use the **decompressed `Image`**, which is what
> `ci/verify.sh`'s reproducibility check does.

### 3) The zip archives themselves: timestamps, gzip headers, DWARF

Once the images matched, the release **archives** still changed on every run. All causes are now removed:

| Source | Symptom | Fix |
|---|---|---|
| `STAMP=$(date -u +%Y%m%d)` | file name followed the build date | derive it from `ci/repro-date.txt` |
| `date:` inside `build-info.txt` | different on every build | use the same `BUILD_TS` |
| mtimes of the zip entries | the wall clock at pack time | normalise with `touch -d "$BUILD_TS"` and pass `zip -X` (drops the extended timestamp field) |
| file name / mtime in the gzip header | `Image.kpm.gz` changed every run | `gzip -9 -n` (the same switch kbuild uses) |
| DWARF inside the `.ko` | include search paths encoded differently | `strip --strip-debug` before packaging (also shrinks 270 KB to 48 KB) |
| zip entry order | followed readdir order, which differs per host | `find ... -printf '%P' \| LC_ALL=C sort \| zip -@` |
| timestamps inside the zip | zip stores **local wall-clock** time; a UTC runner and a UTC+8 host differ by eight hours | run the whole packaging step under `TZ=UTC` |
| `kernel/kheaders.ko` | archives every header; cpio kept the checkout mtimes and tar followed readdir order | `kernel/gen_kheaders.sh`: `touch -d "$KBUILD_BUILD_TIMESTAMP"` + `tar --sort=name --mtime=... --numeric-owner`; **this module is no longer shipped** (see below) |

> `kernel/kheaders.ko` has one more host dependency that cannot be removed: it archives whatever
> generated headers happen to exist in the source tree. A fresh CI clone has none, while a tree that has
> been built in place has 17 (`arch/arm64/include/generated/*`), changing the archive by ~26 KB. The
> module is only an `ikheaders` debugging facility (reading kernel headers at runtime), has no use on a
> phone and weighs 3.3 MB, so `ci/package.sh` **no longer puts it into the modules archive**.

Measured: two consecutive full packaging runs produce **identical hashes for all eight artifacts**
(4 zips + Image.gz + Image.kpm.gz + 2 `.ko` files).

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `asm/types.h: file not found` (in `kernel/bounds.s`) | stale `arch/arm64/include/generated` / `include/generated` in the source tree make kbuild skip regenerating them for the target tree. `ci/build.sh` removes them for from-scratch builds; manually, `rm -rf arch/arm64/include/generated include/generated` first |
| `uname -r` carries a `+` | old behaviour: `scripts/setlocalversion` appends `+` when `LOCALVERSION` is unset and no annotated tag exists. `ci/build.sh` now pins `LOCALVERSION=` so the release string is `4.14.186` |
| `Image` larger than the boot partition | the a22x boot partition is 32 MiB; AK3 uses `Image.gz` (~12 MiB). Never push the uncompressed `Image` (~29 MiB) directly |
| `kptools` complains about GLIBC | the official release binary needs a newer glibc; `ci/kpm_patch.sh` builds it from source instead |
| `pathmask.ko` fails to insmod / vermagic mismatch | the `.ko` must come from the same build as the kernel; never mix versions |
| Working on a repository under `/mnt/d` from WSL is extremely slow | the 9p filesystem forces a full re-hash in git. Keep the repository on a native WSL path (e.g. `~/a226b`) |

## 6. Release process

```bash
git tag v1.4.0
git push origin main --tags
```

A tag push triggers Actions: build → package → upload artifacts → create the release automatically. The
release body comes from `dist/release-body.md` and automatically lists the BakaSU / NoMount revisions and
the KPatch-Next version actually used.
