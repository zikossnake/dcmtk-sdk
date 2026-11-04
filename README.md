# DCMTK SDK

[DCMTK](https://github.com/DCMTK/dcmtk) 3.6.9 with OpenSSL 3.5.4, built as a static
`DCMTK.xcframework` and packaged for Swift Package Manager. This keeps the
[deepecho-mobile-app](https://github.com/Deepecho-org/deepecho-mobile-app) from
carrying the compiled binaries in its own history. Those binaries are 50 MB and
were gitignored, so a fresh clone could not build.

## Contents

| Path | What it is |
| --- | --- |
| `DCMTK.xcframework/ios-arm64/libDCMTK-iphoneos.a` | Device (arm64) |
| `DCMTK.xcframework/ios-arm64_x86_64-simulator/libDCMTK-iphonesimulator.a` | Simulator (arm64 + x86_64) |
| `DCMTK.xcframework/*/Headers` | `dcmtk/` and `openssl/` public headers, plus a `module.modulemap` |
| `scripts/build-openssl-ios.sh` | Builds OpenSSL for iOS from the official release tarball |
| `scripts/make_dcmtk_xcframework.sh` | Builds DCMTK from the official `DCMTK-3.6.9` tag and creates the XCFramework |

Each `.a` merges the DCMTK modules the DICOM SCU needs (`ofstd`, `oflog`,
`oficonv`, `dcmdata`, `dcmnet`, `dcmtls`) with `libssl` and `libcrypto`. The
DICOM data dictionary is compiled in, because iOS has no `DCMDICTPATH` to load
it from.

## Consuming it

```swift
// Tuist/Package.swift
.package(url: "git@github.com:zikossnake/dcmtk-sdk.git", exact: "1.0.0"),
```

```swift
// Project.swift
.external(name: "DCMTK"),
```

Pin with `exact:`. The app's `Tuist/Package.resolved` is gitignored, so a version
range would let different machines link different builds without anyone noticing.

## Rebuilding

Requires `cmake` and `ninja` (`brew install cmake ninja`).

```bash
./scripts/build-openssl-ios.sh --out-dir /tmp/openssl-ios
OPENSSL_IOS_DIR=/tmp/openssl-ios ./scripts/make_dcmtk_xcframework.sh
```

OpenSSL is configured with `no-shared no-tests no-engine no-async no-asm no-dso
no-ui-console`. Change those options and `openssl/configuration.h` changes too.

Then commit, tag the new version, and bump the `exact:` pin in the app.

## Licences

DCMTK is BSD-licensed (OFFIS). OpenSSL 3.x is Apache 2.0.
