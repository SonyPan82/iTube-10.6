#!/bin/bash
# Scripts/build-legacy-ffmpeg.sh
#
# Builds static ffmpeg + ffprobe binaries with -mmacosx-version-min=10.6:
# libmp3lame for MP3 encoding, and ffmpeg's built-in AAC/Opus/Vorbis
# decoders for reading whatever container/codec YouTube served (no
# external decode libraries needed). Apple's VideoToolbox/AudioToolbox/
# AVFoundation hardware paths are disabled since their headers require
# 10.7+.
#
# Unlike Scripts/build-legacy-python.sh, this one works fine on Apple
# Silicon too - it's pure compilation/linking, nothing here needs to
# execute the freshly-built x86_64 binary mid-build.
#
# Usage:
#   chmod +x Scripts/build-legacy-ffmpeg.sh
#   ./Scripts/build-legacy-ffmpeg.sh
#
# Output: Tools/ffmpeg, Tools/ffprobe

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WORK="/tmp/itube-legacy-ffmpeg-build"
LAME_VERSION="3.100"
FFMPEG_VERSION="4.4.5"
DEPLOY_TARGET="10.6"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "== 1/3: libmp3lame ${LAME_VERSION} =="
curl -L -o lame.tar.gz "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"
tar xzf lame.tar.gz
cd "lame-${LAME_VERSION}"
# -march=core2: match the target Mac's actual CPU (2010 Core 2 Duo) so the
# compiler never emits SSE4.2/AVX/etc instructions that CPU doesn't have.
export CC="xcrun clang -arch x86_64 -mmacosx-version-min=${DEPLOY_TARGET} -march=core2"
export CFLAGS="-O2 -march=core2"
./configure --host=x86_64-apple-darwin --enable-static --disable-shared \
    --disable-frontend --prefix="$WORK/lame-out"
make -j"$(sysctl -n hw.ncpu)"
make install
cd "$WORK"

echo "== 2/3: ffmpeg ${FFMPEG_VERSION} =="
curl -L -o ffmpeg.tar.bz2 "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.bz2"
tar xjf ffmpeg.tar.bz2
cd "ffmpeg-${FFMPEG_VERSION}"
export PKG_CONFIG_PATH="$WORK/lame-out/lib/pkgconfig"
# Deliberately NOT using --disable-everything + a curated allowlist here
# anymore: yt-dlp's ffmpeg postprocessors (audio extraction, metadata,
# thumbnail embedding) probe ffmpeg's capabilities and construct command
# lines assuming a normal, reasonably complete build. A hand-picked
# minimal feature set kept turning out to be missing something yt-dlp
# expected ("Option not found" postprocessing errors) - safer to ship a
# near-default ffmpeg build and only cut the pieces that genuinely can't
# work here (network protocols - not needed, we only ever process local
# files; hardware-accelerated encoders needing 10.7+ headers; x86 asm for
# CPU compatibility, same reasoning as -march=core2 elsewhere).
./configure \
    --prefix="$WORK/ffmpeg-out" \
    --arch=x86_64 \
    --target-os=darwin \
    --cc="xcrun clang -arch x86_64 -mmacosx-version-min=${DEPLOY_TARGET} -march=core2" \
    --extra-cflags="-I$WORK/lame-out/include -march=core2" \
    --extra-ldflags="-L$WORK/lame-out/lib -arch x86_64" \
    --disable-shared --enable-static \
    --disable-x86asm \
    --disable-doc --disable-htmlpages --disable-manpages --disable-podpages --disable-txtpages \
    --disable-debug \
    --disable-ffplay \
    --enable-ffprobe \
    --disable-network \
    --disable-avdevice \
    --disable-videotoolbox --disable-audiotoolbox --disable-appkit --disable-coreimage --disable-avfoundation \
    --enable-libmp3lame \
    --enable-swresample \
    --enable-avfilter
make -j"$(sysctl -n hw.ncpu)"
make install
cd "$WORK"

echo "== 3/3: package =="
mkdir -p "$ROOT_DIR/Tools"
cp "$WORK/ffmpeg-out/bin/ffmpeg" "$ROOT_DIR/Tools/ffmpeg"
cp "$WORK/ffmpeg-out/bin/ffprobe" "$ROOT_DIR/Tools/ffprobe"
chmod +x "$ROOT_DIR/Tools/ffmpeg" "$ROOT_DIR/Tools/ffprobe"
codesign --force -s - "$ROOT_DIR/Tools/ffmpeg" "$ROOT_DIR/Tools/ffprobe" 2>/dev/null || true

echo ""
echo "Done: Tools/ffmpeg and Tools/ffprobe are ready."
otool -l "$ROOT_DIR/Tools/ffmpeg" | grep -A2 LC_VERSION_MIN_MACOSX || true
