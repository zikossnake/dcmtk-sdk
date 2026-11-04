#!/usr/bin/env bash
set -euo pipefail

# Builds static OpenSSL for iOS, laid out the way make_dcmtk_xcframework.sh expects:
#   <out>/out-device-arm64/{include,lib}  → device (arm64)
#   <out>/out-sim/{include,lib}           → simulator (arm64 + x86_64, lipo'd)
# Usage: scripts/build-openssl-ios.sh [--out-dir DIR] [--min-ios 15.0]
# Then:  OPENSSL_IOS_DIR=DIR scripts/make_dcmtk_xcframework.sh

OPENSSL_VERSION="3.5.4"
OUT="${OPENSSL_IOS_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/openssl.XXXXXX")}"
MIN_IOS="15.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2 ;;
    --min-ios) MIN_IOS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--out-dir DIR] [--min-ios 15.0]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TARBALL="$OUT/openssl-$OPENSSL_VERSION.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
  echo "• Downloading OpenSSL $OPENSSL_VERSION"
  curl -fsSL -o "$TARBALL" \
    "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
fi

build_target() {
  local target="$1"
  local prefix="$2"
  local min_flag="$3"
  local src="$OUT/src-$target"
  rm -rf "$src"; mkdir -p "$src"
  tar -xzf "$TARBALL" -C "$src" --strip-components 1
  echo "• Building $target"
  ( cd "$src" \
    && ./Configure "$target" no-shared no-tests no-engine no-async no-asm no-dso no-ui-console \
         "$min_flag" --prefix="$prefix" --libdir=lib >/dev/null \
    && make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null \
    && make install_dev >/dev/null )
}

build_target ios64-xcrun               "$OUT/out-device-arm64" "-mios-version-min=$MIN_IOS"
build_target iossimulator-arm64-xcrun  "$OUT/sim-arm64"        "-mios-simulator-version-min=$MIN_IOS"
build_target iossimulator-x86_64-xcrun "$OUT/sim-x86_64"       "-mios-simulator-version-min=$MIN_IOS"

echo "• Merging simulator slices"
rm -rf "$OUT/out-sim"; mkdir -p "$OUT/out-sim/lib"
cp -R "$OUT/sim-arm64/include" "$OUT/out-sim/include"
for lib in libssl.a libcrypto.a; do
  lipo -create "$OUT/sim-arm64/lib/$lib" "$OUT/sim-x86_64/lib/$lib" -output "$OUT/out-sim/lib/$lib"
done

echo "✅ Done: OPENSSL_IOS_DIR=$OUT"
