#!/bin/bash
# Patch the built arm64 Image with KPatch-Next's kpimg so the kernel gains
# KPM (Kernel Patch Module) support at boot. This is an image-level patch:
# no kernel source changes are required.
#
# kptools is built from source here because the release binary requires a
# newer glibc than ubuntu-22.04 provides.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
TAG="${KPATCH_TAG:-0.13.5-2}"
TOOLS="$ROOT/.kpm-tools"

mkdir -p "$TOOLS"

if [ ! -x "$TOOLS/kptools" ]; then
    echo "[+] fetching KPatch-Next source ($TAG)"
    rm -rf "$TOOLS"/KPatch-Next-* "$TOOLS/kpatch-src.tar.gz"
    curl -fL --retry 3 -o "$TOOLS/kpatch-src.tar.gz" \
      "https://github.com/KernelSU-Next/KPatch-Next/archive/refs/tags/${TAG}.tar.gz"
    tar -xzf "$TOOLS/kpatch-src.tar.gz" -C "$TOOLS"
    SRC_DIR="$(find "$TOOLS" -maxdepth 1 -type d -name 'KPatch-Next-*' | head -n1)"
    [ -n "$SRC_DIR" ] || { echo "source dir not found" >&2; exit 1; }
    cp -f "$SRC_DIR/kernel/include/preset.h" "$SRC_DIR/tools/"
    make -C "$SRC_DIR/tools" CC="${CC:-gcc}"
    cp -f "$SRC_DIR/tools/kptools" "$TOOLS/kptools"
fi

if [ ! -f "$TOOLS/kpimg-linux" ]; then
    echo "[+] downloading kpimg-linux ($TAG)"
    curl -fL --retry 3 -o "$TOOLS/kpimg-linux" \
      "https://github.com/KernelSU-Next/KPatch-Next/releases/download/${TAG}/kpimg-linux"
fi

IMG="$OUT/arch/arm64/boot/Image"
PATCHED="$OUT/arch/arm64/boot/Image.kpm"
[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }
rm -f "$PATCHED" "$PATCHED.gz"

echo "[+] patching Image with kpimg $TAG"
"$TOOLS/kptools" -p -i "$IMG" -k "$TOOLS/kpimg-linux" -o "$PATCHED"

echo "[+] verifying patch"
"$TOOLS/kptools" -l -i "$PATCHED" | tee /tmp/kpm_list.txt
grep -q 'patched=true' /tmp/kpm_list.txt

gzip -9 -c "$PATCHED" > "$PATCHED.gz"
ls -lh "$PATCHED" "$PATCHED.gz"
echo KPM_PATCH_OK
