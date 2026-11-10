#!/usr/bin/env bash
set -euo pipefail

# Builds DCMTK.xcframework (static) with two slices:
#   • ios-arm64                  → device
#   • ios-arm64_x86_64-simulator → simulator
#
# DCMTK is configured with the data dictionary COMPILED IN
# (-DDCMTK_DEFAULT_DICT=builtin -DDCMTK_USE_DCMDICTPATH=OFF): iOS has no
# filesystem location to load dicom.dic from, and without the dictionary
# dcmdata cannot resolve tags at runtime.
#
# Only the modules the DICOM SCU needs are built: ofstd, oflog, dcmdata, dcmnet.
# dcmtls is built against OpenSSL, which is compiled for iOS alongside it so the
# SCU can negotiate the DICOM TLS security profiles. OPENSSL_IOS_DIR must point at
# a tree holding out-device-arm64/ and out-sim/ (see build-openssl-ios.sh).

DCMTK_VERSION="DCMTK-3.6.9"
WORK="${DCMTK_WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/dcmtk.XXXXXX")}"
OUTPUT_DIR="."
NAME="DCMTK"
MIN_IOS="15.0"
MODULES=(ofstd oflog dcmdata dcmnet dcmtls)
LIBS=(libdcmtls.a libdcmnet.a libdcmdata.a liboflog.a libofstd.a liboficonv.a)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)   WORK="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --min-ios)    MIN_IOS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--work-dir DIR] [--output-dir DIR] [--min-ios 15.0]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

command -v cmake >/dev/null || { echo "ERROR: cmake not found (brew install cmake)"; exit 1; }
command -v ninja >/dev/null || { echo "ERROR: ninja not found (brew install ninja)"; exit 1; }

SRC="$WORK/src"
if [[ ! -d "$SRC" ]]; then
  echo "• Cloning $DCMTK_VERSION"
  git clone -q --depth 1 --branch "$DCMTK_VERSION" https://github.com/DCMTK/dcmtk.git "$SRC"
fi

configure_and_build() {
  local sdk="$1"
  local openssl_root="$2"
  local archs="$3"
  local build="$WORK/build-$sdk"
  echo "• Configuring $sdk ($archs)"
  cmake -S "$SRC" -B "$build" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF \
    -DDCMTK_DEFAULT_DICT=builtin -DDCMTK_USE_DCMDICTPATH=OFF \
    -DDCMTK_WITH_OPENSSL=ON \
    -DOPENSSL_ROOT_DIR="$openssl_root" \
    -DOPENSSL_INCLUDE_DIR="$openssl_root/include" \
    -DOPENSSL_SSL_LIBRARY="$openssl_root/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_root/lib/libcrypto.a" \
    -DDCMTK_WITH_ZLIB=OFF -DDCMTK_WITH_PNG=OFF \
    -DDCMTK_WITH_TIFF=OFF -DDCMTK_WITH_XML=OFF -DDCMTK_WITH_ICONV=OFF \
    -DDCMTK_WITH_ICU=OFF -DDCMTK_WITH_SNDFILE=OFF -DDCMTK_WITH_WRAP=OFF \
    -DDCMTK_WITH_THREADS=ON >/dev/null
  echo "• Building $sdk"
  cmake --build "$build" --target "${MODULES[@]}" -j"$(sysctl -n hw.ncpu)" >/dev/null
  echo "• Merging static libraries for $sdk"
  ( cd "$build/lib" && libtool -static -o "$WORK/lib$NAME-$sdk.a" "${LIBS[@]}" \
      "$openssl_root/lib/libssl.a" "$openssl_root/lib/libcrypto.a" 2>/dev/null )
}

OPENSSL_IOS_DIR="${OPENSSL_IOS_DIR:-$WORK/../openssl}"
configure_and_build iphoneos        "$OPENSSL_IOS_DIR/out-device-arm64" arm64
configure_and_build iphonesimulator "$OPENSSL_IOS_DIR/out-sim"          "arm64;x86_64"

echo "• Collecting headers"
HEADERS="$WORK/Headers"
rm -rf "$HEADERS"; mkdir -p "$HEADERS/dcmtk"
for m in config "${MODULES[@]}"; do
  cp -R "$SRC/$m/include/dcmtk/$m" "$HEADERS/dcmtk/"
done
cp "$WORK/build-iphoneos/config/include/dcmtk/config/osconfig.h" "$HEADERS/dcmtk/config/osconfig.h"

# OpenSSL public headers travel with the framework: the certificate bridge reads
# X509 fields through the OpenSSL API rather than parsing DER by hand.
cp -R "$OPENSSL_IOS_DIR/out-device-arm64/include/openssl" "$HEADERS/openssl"

# The module map sits in the dcmtk/ folder, not at the root of Headers/: Xcode copies the
# headers of every static XCFramework into one include/ directory, so a root module.modulemap
# collides with any other library that ships one there (deepecho_imagingFFI in the app).
cat > "$HEADERS/dcmtk/module.modulemap" <<EOF
module $NAME {
    umbrella "."
    export *
    requires cplusplus
}
EOF

OUT="$OUTPUT_DIR/$NAME.xcframework"
rm -rf "$OUT"; mkdir -p "$OUTPUT_DIR"
echo "• Creating $OUT"
xcodebuild -create-xcframework \
  -library "$WORK/lib$NAME-iphoneos.a"        -headers "$HEADERS" \
  -library "$WORK/lib$NAME-iphonesimulator.a" -headers "$HEADERS" \
  -output "$OUT" >/dev/null

du -sh "$OUT"
echo "✅ Done: $OUT"
