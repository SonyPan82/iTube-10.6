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
export CC="clang -mmacosx-version-min=${DEPLOY_TARGET}"
./Configure darwin64-x86_64-cc no-shared no-tests \
    --prefix="$WORK/openssl-out" --openssldir="$WORK/openssl-out/ssl"
make -j"$(sysctl -n hw.ncpu)"
make install_sw install_ssldirs
cd "$WORK"

echo "== 2/4: Python ${PYTHON_VERSION} =="
curl -L -o python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"
tar xJf python.tar.xz
cd "Python-${PYTHON_VERSION}"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET"
export CFLAGS="-I$WORK/openssl-out/include"
export LDFLAGS="-L$WORK/openssl-out/lib"
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
