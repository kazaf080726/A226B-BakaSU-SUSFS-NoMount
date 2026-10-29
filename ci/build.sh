#!/bin/bash
# Build the SM-A226B (a22x) 4.14.186 kernel with BakaSU + SUSFS + NoMount.
# Assumes toolchain/ and the KernelSU/ + NoMount/ clones already exist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export ARCH=arm64
export SUBARCH=arm64
export PATH="$ROOT/toolchain/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$ROOT/toolchain/clang/host/linux-x86/clang-r383902/bin:$PATH"
export CROSS_COMPILE="aarch64-linux-androidkernel-"
export CLANG_TRIPLE="aarch64-linux-gnu-"
unset CC LD AR NM STRIP OBJCOPY OBJDUMP READELF HOSTCC HOSTCXX || true

JOBS="${JOBS:-$(nproc)}"
OUT="${OUT:-$ROOT/out}"
DEFCONFIG="${DEFCONFIG:-a22x_defconfig}"

mkdir -p "$OUT"
echo "=== [$DEFCONFIG] BakaSU: $(git -C KernelSU rev-parse --short=12 HEAD 2>/dev/null || echo '?')"
echo "=== [$DEFCONFIG] NoMount: $(git -C NoMount rev-parse --short=12 HEAD 2>/dev/null || echo '?')"
make -C "$ROOT" O="$OUT" ARCH=arm64 "$DEFCONFIG"
make -C "$ROOT" O="$OUT" ARCH=arm64 -j"$JOBS" \
    KCFLAGS=-w CONFIG_SECTION_MISMATCH_WARN_ONLY=y

ls -lh "$OUT/arch/arm64/boot/Image" "$OUT/arch/arm64/boot/Image.gz"
