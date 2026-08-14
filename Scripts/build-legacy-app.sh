#!/bin/bash
# Scripts/build-legacy-app.sh
#
# Builds the main iTube.app binary against the authentic Mac OS X 10.6 SDK,
# linked with the genuine ld64 linker from Xcode 3.2.6 - not just modern
# clang with -mmacosx-version-min=10.6.
#
# WHY: -mmacosx-version-min alone is not enough. A binary built with a
# recent Xcode toolchain (even targeting 10.6) records the CURRENT
# machine's framework version numbers (e.g. AppKit 2685.x) instead of the
# real Snow Leopard ones (AppKit 1038.x) in its LC_LOAD_DYLIB commands,
# and real Snow Leopard hardware crashes at launch on that mismatch. The
# only reliable fix is linking against the real 10.6 SDK's dylib stubs
# with the real period-correct linker.
#
# Also targets -march=core2: the oldest realistic Mac in the 10.6-10.9
# range has a Core 2 Duo CPU, which lacks SSE4.2/AVX/etc. Compiling
# without this flag produces code that crashes with "illegal instruction"
# the moment it hits an auto-vectorized loop using a newer instruction
# than the target CPU has - this bit us hard during testing (see git log).
#
# Prerequisites:
#   - Toolchain/SDKs/MacOSX10.6.sdk  (see Docs/BUILD_LEGACY.md)
#   - Toolchain/bin/ld-legacy        (ld64-97.17, extracted from the same
#                                      Xcode 3.2.6 installer's
#                                      DeveloperToolsCLI.pkg -> usr/bin/ld
#                                      - proprietary, never commit it)
#
# Usage:
#   chmod +x Scripts/build-legacy-app.sh
#   ./Scripts/build-legacy-app.sh
#
# Output: build/iTube_legacy.app (unsigned - Snow Leopard has no Gatekeeper
# and doesn't need one; a modern ad-hoc signature's SHA-256 CodeDirectory
# format isn't understood by 10.6's kernel anyway).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SDK="$ROOT_DIR/Toolchain/SDKs/MacOSX10.6.sdk"
LD="$ROOT_DIR/Toolchain/bin/ld-legacy"
BUILD_DIR="$ROOT_DIR/build/iTube_legacy.app"
OBJ_DIR="$(mktemp -d)"

if [ ! -d "$SDK" ]; then
    echo "ERROR: $SDK not found. See Docs/BUILD_LEGACY.md to extract it." >&2
    exit 1
fi
if [ ! -x "$LD" ]; then
    echo "ERROR: $LD not found. Extract it from Xcode 3.2.6's" >&2
    echo "DeveloperToolsCLI.pkg (Payload/usr/bin/ld) - see Docs/BUILD_LEGACY.md." >&2
    exit 1
fi

echo "== Compiling =="
for f in "$ROOT_DIR"/YTubeMP3/*.m; do
    name=$(basename "$f" .m)
    xcrun clang -arch x86_64 -fno-objc-arc -mmacosx-version-min=10.6 -march=core2 \
        -isysroot "$SDK" \
        -c "$f" -o "$OBJ_DIR/${name}.o"
done

echo "== Linking (genuine ld64-97.17, real 10.6 SDK) =="
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources"
"$LD" -arch x86_64 -macosx_version_min 10.6 \
    -syslibroot "$SDK" \
    -o "$BUILD_DIR/Contents/MacOS/iTube" \
    "$SDK/usr/lib/crt1.o" \
    "$OBJ_DIR"/*.o \
    -framework Cocoa \
    -lobjc -lSystem

echo "== Assembling bundle =="
cp "$ROOT_DIR/YTubeMP3/Info.plist" "$BUILD_DIR/Contents/Info.plist"
printf 'APPL????' > "$BUILD_DIR/Contents/PkgInfo"
cp "$ROOT_DIR/YTubeMP3/icon.icns" "$BUILD_DIR/Contents/Resources/icon.icns"
mkdir -p "$BUILD_DIR/Contents/Resources/en.lproj" "$BUILD_DIR/Contents/Resources/fr.lproj"
cp "$ROOT_DIR/YTubeMP3/en.lproj/Localizable.strings" "$BUILD_DIR/Contents/Resources/en.lproj/"
cp "$ROOT_DIR/YTubeMP3/fr.lproj/Localizable.strings" "$BUILD_DIR/Contents/Resources/fr.lproj/"
if [ -d "$ROOT_DIR/Tools" ]; then
    cp -R "$ROOT_DIR/Tools" "$BUILD_DIR/Contents/Resources/Tools"
fi

echo "== Stripping any code signature =="
# Snow Leopard predates Gatekeeper entirely and never checks signatures at
# launch - but a modern ad-hoc signature's SHA-256 CodeDirectory format
# can still confuse the old kernel if present, so ship fully unsigned.
find "$BUILD_DIR" -type f -perm -u+x ! -name "*.py" -exec codesign --remove-signature {} \; 2>/dev/null || true
codesign --remove-signature "$BUILD_DIR" 2>/dev/null || true

rm -rf "$OBJ_DIR"
echo ""
echo "Done: $BUILD_DIR"
