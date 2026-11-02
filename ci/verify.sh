#!/bin/bash
# Post-build gate: the three things that actually break a release.
#
#   1. the kernel must fit the boot partition next to the stock ramdisk/dtb
#   2. the PathMask modules must carry exactly the kernel's vermagic
#   3. (optional, slow) two clean builds must produce identical images
#
# Run after ci/package.sh and pathmask/build.sh. Exits non-zero on failure so a
# broken tag never gets published.
#
# Deliberately no `set -e`: failures are accumulated into $fail and reported
# together, so one broken artifact does not hide the others.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
# a22x boot partition is 32 MiB; stock ramdisk ~1.94 MiB and dtb ~158 KiB.
BOOT_PARTITION_BYTES=$((32 * 1024 * 1024))
PAYLOAD_BUDGET=$((BOOT_PARTITION_BYTES - 4 * 1024 * 1024))	# 4 MiB headroom

fail=0
note() { printf '%-6s %s\n' "$1" "$2"; }

echo "=== 1. image size ==="
IMG="$OUT/arch/arm64/boot/Image.gz"
[ -f "$IMG" ] || IMG="$OUT/arch/arm64/boot/Image"
if [ ! -f "$IMG" ]; then
	note FAIL "no Image/Image.gz under $OUT"
	fail=1
else
	sz=$(stat -c %s "$IMG")
	note ok "$(basename "$IMG") = $sz bytes, budget $PAYLOAD_BUDGET bytes"
	if [ "$sz" -gt "$PAYLOAD_BUDGET" ]; then
		note FAIL "kernel exceeds the boot partition budget"
		fail=1
	fi
fi

echo
echo "=== 2. module vermagic ==="
rel=$(cat "$OUT/include/config/kernel.release" 2>/dev/null || echo "?")
expected=$(strings -a "$OUT/vmlinux" 2>/dev/null | grep -E "^${rel} SMP.* aarch64$" | head -n1)
[ -n "$expected" ] || expected="${rel} SMP preempt mod_unload modversions aarch64"
note info "kernel expects: $expected"
for ko in "$ROOT/pathmask/src/pathmask.ko" "$ROOT/pathmask/src/procguard.ko"; do
	if [ ! -f "$ko" ]; then
		note FAIL "missing $(basename "$ko") (run pathmask/build.sh first)"
		fail=1
		continue
	fi
	got=$(strings -a "$ko" | grep -m1 '^vermagic=' | cut -d= -f2-)
	if [ "$got" = "$expected" ]; then
		note ok "$(basename "$ko"): $got"
	else
		note FAIL "$(basename "$ko"): '$got' != '$expected'"
		fail=1
	fi
done

echo
echo "=== 3. reproducible build (optional) ==="
if [ "${REPRO_CHECK:-0}" = "1" ]; then
	first=$(sha256sum "$IMG" | cut -d' ' -f1)
	note info "first build : $first"
	rm -rf "$OUT"
	if ( cd "$ROOT" && bash ci/build.sh >/dev/null 2>&1 ); then
		second=$(sha256sum "$IMG" | cut -d' ' -f1)
		if [ "$first" = "$second" ]; then
			note ok "second build identical: $second"
		else
			note FAIL "second build differs: $second"
			fail=1
		fi
	else
		note FAIL "rebuild failed"
		fail=1
	fi
else
	note skip "set REPRO_CHECK=1 to rebuild and compare (adds ~15 min)"
fi

echo
if [ "$fail" -ne 0 ]; then
	echo "VERIFY_FAILED"
	exit 1
fi
echo "VERIFY_OK"
