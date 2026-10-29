#!/bin/bash
# Download the exact toolchain used by Samsung for this kernel:
#   AOSP clang r383902 + AArch64 GCC 4.9 binutils.
# The kernel Makefile expects them at <kernel>/toolchain/... .
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="$ROOT/toolchain"

CLANG_DIR="$TC/clang/host/linux-x86/clang-r383902"
GCC_DIR="$TC/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"

if [ ! -x "$CLANG_DIR/bin/clang" ]; then
    echo "[+] downloading clang-r383902"
    mkdir -p "$TC/clang/host/linux-x86"
    tmp=$(mktemp)
    curl -fL --retry 3 -o "$tmp" \
      "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android11-release/clang-r383902.tar.gz"
    rm -rf "$CLANG_DIR"; mkdir -p "$CLANG_DIR"
    tar -xzf "$tmp" -C "$CLANG_DIR"
    rm -f "$tmp"
fi

if [ ! -x "$GCC_DIR/bin/aarch64-linux-androidkernel-ld" ]; then
    echo "[+] downloading gcc-4.9 binutils"
    mkdir -p "$TC/gcc/linux-x86/aarch64"
    tmp=$(mktemp)
    curl -fL --retry 3 -o "$tmp" \
      "https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/heads/android11-release.tar.gz"
    rm -rf "$GCC_DIR"; mkdir -p "$GCC_DIR"
    tar -xzf "$tmp" -C "$GCC_DIR"
    rm -f "$tmp"
fi

"$CLANG_DIR/bin/clang" --version | head -2
"$GCC_DIR/bin/aarch64-linux-androidkernel-ld" --version | head -1
echo "[+] toolchain ready"
