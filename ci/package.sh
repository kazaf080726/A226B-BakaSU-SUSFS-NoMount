#!/bin/bash
# Package Image.gz + AnyKernel3 flashable zip + kernel modules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${OUT:-$ROOT/out}"
DIST="$ROOT/dist"
ARTIFACT_NAME="${ARTIFACT_NAME:-A226B-BakaSU-SUSFS-NoMount}"
# Reproducibility: the zip name, the embedded build date and every entry's mtime
# must not depend on when the build ran, otherwise two builds of the same commit
# produce different archives. Drive all three from the pinned timestamp.
if [ -n "${KBUILD_BUILD_TIMESTAMP:-}" ]; then
    BUILD_TS="$KBUILD_BUILD_TIMESTAMP"
elif [ -f "$ROOT/ci/repro-date.txt" ]; then
    BUILD_TS="$(head -n1 "$ROOT/ci/repro-date.txt")"
else
    BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
if [ -f "$ROOT/ci/repro-date.txt" ]; then
    STAMP="$(date -u -d "$(head -n1 "$ROOT/ci/repro-date.txt")" +%Y%m%d 2>/dev/null || date -u +%Y%m%d)"
else
    STAMP="$(date -u +%Y%m%d)"
fi

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
  echo "date:   $BUILD_TS"
} > "$AK/build-info.txt"

find "$AK" -exec touch -h -d "$BUILD_TS" {} + 2>/dev/null || true
# zip stores DOS timestamps in *local* wall-clock time, so TZ must be pinned or
# a UTC runner and a UTC+8 workstation disagree by eight hours. Entry order also
# follows readdir order unless it is imposed here, and that differs between
# hosts. Sort the names and feed them through -@ so both sides agree.
TZ=UTC LC_ALL=C find "$AK" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort \
    | ( cd "$AK" && TZ=UTC zip -X -9 -@ "$DIST/$ARTIFACT_NAME-$STAMP.zip" >/dev/null )
cp -f "$OUT/arch/arm64/boot/Image.gz" "$DIST/Image.gz" 2>/dev/null || cp -f "$OUT/arch/arm64/boot/Image" "$DIST/Image"

# collect modules (if any)
MODS=$(find "$OUT" -name '*.ko' -type f 2>/dev/null | wc -l)
if [ "$MODS" -gt 0 ]; then
    mkdir -p "$DIST/modules"
    ( cd "$OUT" && find . -name '*.ko' -type f -exec cp --parents {} "$DIST/modules/" \; )
    find "$DIST/modules" -exec touch -h -d "$BUILD_TS" {} + 2>/dev/null || true
    TZ=UTC LC_ALL=C find "$DIST/modules" \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort \
        | ( cd "$DIST/modules" && TZ=UTC zip -X -9 -@ "$DIST/$ARTIFACT_NAME-modules-$STAMP.zip" >/dev/null )
fi

ls -lh "$DIST"
