#!/bin/bash
# Package Image.gz + AnyKernel3 flashable zip + kernel modules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${OUT:-$ROOT/out}"
DIST="$ROOT/dist"
ARTIFACT_NAME="${ARTIFACT_NAME:-A226B-BakaSU-SUSFS-NoMount}"
STAMP="$(date -u +%Y%m%d)"

rm -rf "$DIST"; mkdir -p "$DIST"
AK="$DIST/ak3"
cp -a "$ROOT/anykernel" "$AK"

if [ -f "$OUT/arch/arm64/boot/Image.gz" ]; then
    cp -f "$OUT/arch/arm64/boot/Image.gz" "$AK/Image.gz"
elif [ -f "$OUT/arch/arm64/boot/Image" ]; then
    cp -f "$OUT/arch/arm64/boot/Image" "$AK/Image"
else
    echo "no kernel image found" >&2; exit 1
fi

# record build metadata inside the zip
{
  echo "kernel: 4.14.186 (Samsung SM-A226B source)"
  echo "bakasu: $(git -C "$ROOT/KernelSU" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "susfs:  $(grep -m1 '^#define SUSFS_VERSION' "$ROOT/include/linux/susfs.h" | cut -d'"' -f2)"
  echo "nomount: $(git -C "$ROOT/NoMount" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$AK/build-info.txt"

( cd "$AK" && zip -r9 "$DIST/$ARTIFACT_NAME-$STAMP.zip" . -x '*.git*' >/dev/null )
cp -f "$OUT/arch/arm64/boot/Image.gz" "$DIST/Image.gz" 2>/dev/null || cp -f "$OUT/arch/arm64/boot/Image" "$DIST/Image"

# collect modules (if any)
MODS=$(find "$OUT" -name '*.ko' -type f 2>/dev/null | wc -l)
if [ "$MODS" -gt 0 ]; then
    mkdir -p "$DIST/modules"
    ( cd "$OUT" && find . -name '*.ko' -type f -exec cp --parents {} "$DIST/modules/" \; )
    ( cd "$DIST/modules" && zip -r9 "$DIST/$ARTIFACT_NAME-modules-$STAMP.zip" . >/dev/null )
fi

ls -lh "$DIST"
