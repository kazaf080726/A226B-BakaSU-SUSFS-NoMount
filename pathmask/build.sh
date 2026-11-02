#!/bin/bash
# Build the 4.14-ported PathMask/procguard LKMs and package them as a
# KernelSU module zip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
DIST="$ROOT/dist"
STAMP="$(date -u +%Y%m%d)"
TC="$ROOT/toolchain"

export ARCH=arm64
export SUBARCH=arm64
export PATH="$TC/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$TC/clang/host/linux-x86/clang-r383902/bin:$PATH"
export CROSS_COMPILE="aarch64-linux-androidkernel-"
export CLANG_TRIPLE="aarch64-linux-gnu-"
unset CC LD AR NM STRIP OBJCOPY OBJDUMP READELF HOSTCC HOSTCXX || true

echo "[+] building PathMask LKMs against $OUT"
# Reproducibility: modules are built with an absolute M= path, so __FILE__ and
# the DWARF strings used to embed /home/runner/work/... on CI and
# /home/kali/... locally -- by itself that made the two .ko differ by ~1.3 KiB.
# KCFLAGS reaches every compilation unit (including the generated .mod.c),
# whereas ccflags-y did not; the map is applied to the kernel tree prefix only.
make -C "$ROOT" O="$OUT" ARCH=arm64 M="$ROOT/pathmask/src" \
     KCFLAGS="-ffile-prefix-map=$ROOT/=" modules

MOD="$ROOT/pathmask/ksu-module"
cp -f "$ROOT/pathmask/src/pathmask.ko" "$MOD/pathmask.ko"
cp -f "$ROOT/pathmask/src/procguard.ko" "$MOD/procguard.ko"

mkdir -p "$DIST"
( cd "$MOD" && zip -r9 "$DIST/A226B-PathMask-4.14-$STAMP.zip" . -x '*.git*' >/dev/null )
cp -f "$ROOT/pathmask/src/pathmask.ko" "$DIST/pathmask-4.14.ko"
cp -f "$ROOT/pathmask/src/procguard.ko" "$DIST/procguard-4.14.ko"

ls -lh "$DIST/A226B-PathMask-4.14-$STAMP.zip" "$DIST/pathmask-4.14.ko" "$DIST/procguard-4.14.ko"
echo PATHMASK_BUILD_OK
