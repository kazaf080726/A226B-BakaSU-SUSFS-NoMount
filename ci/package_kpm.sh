#!/bin/bash
# Package the KPM-enabled kernel into a second AnyKernel3 zip.
# Flash this only if you need KPM; keep the standard zip as fallback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
DIST="$ROOT/dist"
ARTIFACT_NAME="${ARTIFACT_NAME:-A226B-BakaSU-SUSFS-NoMount-KPM}"
STAMP="$(date -u +%Y%m%d)"

KIMG="$OUT/arch/arm64/boot/Image.kpm.gz"
[ -f "$KIMG" ] || { echo "missing $KIMG (run ci/kpm_patch.sh first)" >&2; exit 1; }

mkdir -p "$DIST"
AK="$DIST/ak3-kpm"
rm -rf "$AK"
cp -a "$ROOT/anykernel" "$AK"
cp -f "$KIMG" "$AK/Image.gz"

{
  echo "kernel: 4.14.186 (Samsung SM-A226B source)"
  echo "kpm: KPatch-Next kpimg ${KPATCH_TAG:-0.13.5-2} (Image pre-patched)"
  echo "bakasu: $(git -C "$ROOT/KernelSU" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "susfs:  $(grep -m1 '^#define SUSFS_VERSION' "$ROOT/include/linux/susfs.h" | cut -d'"' -f2)"
  echo "nomount: $(git -C "$ROOT/NoMount" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$AK/build-info.txt"

( cd "$AK" && zip -r9 "$DIST/$ARTIFACT_NAME-$STAMP.zip" . -x '*.git*' >/dev/null )
cp -f "$KIMG" "$DIST/Image.kpm.gz"
ls -lh "$DIST/$ARTIFACT_NAME-$STAMP.zip" "$DIST/Image.kpm.gz"
echo KPM_PACKAGE_OK
