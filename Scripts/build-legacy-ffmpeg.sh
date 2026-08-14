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
export CC="xcrun clang -arch x86_64 -mmacosx-version-min=${DEPLOY_TARGET}"
export CFLAGS="-O2"
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
./configure \
    --prefix="$WORK/ffmpeg-out" \
    --arch=x86_64 \
    --target-os=darwin \
    --cc="xcrun clang -arch x86_64 -mmacosx-version-min=${DEPLOY_TARGET}" \
    --extra-cflags="-I$WORK/lame-out/include" \
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
    --disable-everything \
    --enable-protocol=file \
    --enable-demuxer=mov,matroska,webm,mp4,m4a,aac,wav,ogg,flac,mp3,image2 \
    --enable-decoder=aac,aac_latm,opus,vorbis,flac,mp3,pcm_s16le,pcm_s16be,alac,webp,png,mjpeg \
    --enable-encoder=libmp3lame,mjpeg,png \
    --enable-muxer=mp3,image2 \
    --enable-parser=aac,opus,vorbis,flac,mpegaudio,mjpeg,png,webp \
    --enable-filter=aresample,anull \
    --enable-swresample \
    --enable-avfilter \
    --enable-small
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
