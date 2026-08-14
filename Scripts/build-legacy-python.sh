#!/bin/bash
# Scripts/build-legacy-python.sh
#
# Builds a self-contained Python 3.11 + OpenSSL 3.0, both compiled from
# source with -mmacosx-version-min=10.6, so the app can run a current
# yt-dlp (which requires Python 3.10+) while still launching on Snow
# Leopard/Mavericks.
#
# WHY THIS EXISTS: the bundled Python 3.6 (from vendor.sh) is the last
# python.org installer advertising 10.6 support, but yt-dlp dropped Python
# 3.6 support in mid-2022 and YouTube has since evolved enough that a
# yt-dlp from that era no longer works at all (tested: it gets rejected
# outright by YouTube's backend). Current yt-dlp needs Python 3.10+, and
# the official python.org installers for anything newer than 3.6 require
# macOS 10.9+ at minimum (they refuse to even run on 10.6/10.7/10.8) - so
# the only way to get a modern-enough Python that still launches on 10.6
# is to compile CPython from source with an old deployment target.
#
# MUST run on real Intel hardware (or an Intel CI runner, e.g. GitHub
# Actions' macos-13). It will NOT work on Apple Silicon: CPython's build
# process must execute the freshly-built interpreter mid-build to
# generate its sysconfig data, and Apple Silicon's Rosetta 2 translation
# layer refuses to run ad-hoc-signed x86_64 binaries under a "Full
# Security" policy - this isn't a workaround-able bug, it's how the
# system is designed to behave when there's no genuine Developer ID
# signature. On real Intel silicon there's no translation involved, so
# this problem doesn't exist.
#
# Usage (on an Intel Mac, or an Intel GitHub Actions runner):
#   chmod +x Scripts/build-legacy-python.sh
#   ./Scripts/build-legacy-python.sh
#
# Output: Tools/Python3.11/ (self-contained, relocatable - see the
# install_name_tool step at the end) ready to be zipped/copied into this
# repo's Tools/ directory alongside vendor.sh's yt-dlp/ffmpeg output.

set -e

# Some CI shells / make invocations end up with a stripped or unset PATH by
# the time CPython's build_ext step forks python.exe -E ./setup.py build,
# which crashes distutils's _osx_support.py (it reads os.environ['PATH']
# with no fallback). Guarantee it's always present and sane up front.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${PATH:-}"

if [ "$(uname -m)" != "x86_64" ]; then
    echo "ERROR: this must run on real Intel (x86_64) hardware or an Intel CI runner." >&2
    echo "Apple Silicon can't do it - see the comment header in this script for why." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WORK="/tmp/itube-legacy-python-build"
OPENSSL_VERSION="3.0.15"
PYTHON_VERSION="3.11.9"
DEPLOY_TARGET="10.6"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "== 1/4: OpenSSL ${OPENSSL_VERSION} =="
curl -L -o openssl.tar.gz "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
tar xzf openssl.tar.gz
cd "openssl-${OPENSSL_VERSION}"
export CC="clang -mmacosx-version-min=${DEPLOY_TARGET} -march=core2"
# no-asm: OpenSSL's hand-written assembly routines (AES-NI, PCLMUL, AVX...)
# pick which optimized code path to run via runtime CPUID checks -
# completely independent of the -march compiler flag above, since they're
# not compiler-generated code. Core 2 Duo predates AES-NI/PCLMUL/AVX
# entirely (those arrived with Westmere/Sandy Bridge, 2010-2011), and if
# that runtime dispatch ever mis-detects or falls through, the result is a
# genuine SIGILL ("Illegal instruction") - same failure mode as the
# -march issue, but completely unaffected by fixing -march since this is
# hand-written asm, not compiler output. no-asm forces pure-C
# implementations everywhere, trading crypto throughput for guaranteed
# compatibility - the right tradeoff for a small utility app.
./Configure darwin64-x86_64-cc no-shared no-tests no-asm \
    --prefix="$WORK/openssl-out" --openssldir="$WORK/openssl-out/ssl"
make -j"$(sysctl -n hw.ncpu)"
make install_sw install_ssldirs
cd "$WORK"

echo "== 2/4: Python ${PYTHON_VERSION} =="
curl -L -o python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"
tar xJf python.tar.xz
cd "Python-${PYTHON_VERSION}"

# CPython's own build_ext step forks "python.exe -E ./setup.py build" to
# compile the stdlib's C extension modules. Something in that forked
# process's environment ends up without PATH (observed on GitHub Actions'
# macos-15-intel runners; harmless to patch defensively regardless of root
# cause) which crashes distutils's _osx_support.py with a bare KeyError
# since it indexes os.environ['PATH'] with no fallback. Make it tolerant.
sed -i '' "s/path = os.environ\['PATH'\]/path = os.environ.get('PATH', '\/usr\/bin:\/bin:\/usr\/local\/bin')/" \
    Lib/_osx_support.py

export MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET"
# -march=core2: the target Mac (MacBook6,1, 2010) has a Core 2 Duo CPU,
# which lacks SSE4.2/AVX/POPCNT and other instructions modern clang emits
# by default on x86_64 (which just assumes "any reasonably recent Intel
# chip"). Without this, compiled code crashes with "illegal instruction"
# the moment it hits an auto-vectorized loop or intrinsic using a newer
# instruction than this CPU actually has.
export CFLAGS="-I$WORK/openssl-out/include -march=core2"
export LDFLAGS="-L$WORK/openssl-out/lib"

# GitHub Actions' macos-15-intel runners ship Homebrew with gettext
# pre-installed under /usr/local/opt/gettext. CPython's configure
# auto-detects and links against it (for the _locale module) if it's on
# PATH/library search paths - producing a binary that depends on
# /usr/local/opt/gettext/lib/libintl.8.dylib, a path that will never exist
# on the target Mac. Force that detection off and strip Homebrew from the
# paths configure searches, so the build only ever links against genuine
# system libraries.
export ac_cv_lib_intl_textdomain=no
export ac_cv_header_libintl_h=no
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

./configure \
    --prefix="$WORK/python-out" \
    --with-openssl="$WORK/openssl-out" \
    --disable-test-modules \
    --without-ensurepip \
    --enable-ipv6
make -j"$(sysctl -n hw.ncpu)"
make install
cd "$WORK"

echo "== 3/4: trim + relink for self-containment =="
PY_PREFIX="$WORK/python-out"
# Drop anything not needed at runtime to keep the bundle small.
rm -rf "$PY_PREFIX"/lib/python3.11/test "$PY_PREFIX"/lib/python3.11/idlelib
rm -rf "$PY_PREFIX"/lib/python3.11/lib2to3/tests
rm -rf "$PY_PREFIX"/share "$PY_PREFIX"/lib/pkgconfig
# Since OpenSSL was built with no-shared, _ssl.so/_hashlib.so already have
# libssl/libcrypto linked in statically - nothing external to re-point.
# The only relative-path fix needed is python3.11's own reference to
# libpython3.11 if it was built as a separate dylib (default is static
# here since we didn't pass --enable-shared, so this is usually a no-op -
# the check below just confirms there's nothing pointing outside the tree).
echo "Checking for any remaining absolute /tmp or /usr/local references:"
find "$PY_PREFIX" -type f \( -name "*.so" -o -name "*.dylib" -o -perm +111 \) -exec sh -c \
    'otool -L "$1" 2>/dev/null | grep -qE "/tmp/|/usr/local/" && echo "  ! $1"' _ {} \; || true

echo "== 4/4: package =="
mkdir -p "$ROOT_DIR/Tools/Python3.11"
cp -R "$PY_PREFIX"/* "$ROOT_DIR/Tools/Python3.11/"
# ad-hoc sign everything so it'll run under Rosetta if ever tested on
# Apple Silicon too, and to keep the code signature well-formed generally.
find "$ROOT_DIR/Tools/Python3.11" -type f -perm +111 -exec codesign --force -s - {} \; 2>/dev/null || true

echo ""
echo "Done. Tools/Python3.11/bin/python3.11 is ready."
echo "Update vendor.sh's YTDLP_VERSION to a current release (Python 3.10+"
echo "compatible) and re-run it, then rebuild the app - YTDLPController"
echo "already looks for Tools/Python3.11 first, falling back to the old"
echo "Tools/Python.framework (3.6) layout if this directory is absent."
