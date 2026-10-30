#!/bin/bash
# Patch the built arm64 Image with KPatch-Next's kpimg so the kernel gains
# KPM (Kernel Patch Module) support at boot. This is an image-level patch:
# no kernel source changes are required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
TAG="${KPATCH_TAG:-0.13.5-2}"
TOOLS="$ROOT/.kpm-tools"

mkdir -p "$TOOLS"
if [ ! -x "$TOOLS/kptools-linux" ]; then
    echo "[+] downloading kptools-linux ($TAG)"
    curl -fL --retry 3 -o "$TOOLS/kptools-linux" \
      "https://github.com/KernelSU-Next/KPatch-Next/releases/download/${TAG}/kptools-linux"
    chmod +x "$TOOLS/kptools-linux"
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
"$TOOLS/kptools-linux" -p -i "$IMG" -k "$TOOLS/kpimg-linux" -o "$PATCHED"

echo "[+] verifying patch"
"$TOOLS/kptools-linux" -l -i "$PATCHED" | tee /tmp/kpm_list.txt
grep -q 'patched=true' /tmp/kpm_list.txt

gzip -9 -c "$PATCHED" > "$PATCHED.gz"
ls -lh "$PATCHED" "$PATCHED.gz"
echo KPM_PATCH_OK
