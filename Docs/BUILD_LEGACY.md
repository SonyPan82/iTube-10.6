# Building the real 10.6-targeted binary

iTube's release binary is compiled **and linked** against the real Mac OS X
10.6 SDK and the genuine period linker, so it links against nothing newer
than what Snow Leopard actually shipped. `-mmacosx-version-min=10.6` alone
is *not* enough: a binary built with a modern Xcode toolchain still records
the *current* machine's framework version numbers (e.g. AppKit 2685.x
instead of the real Snow Leopard 1038.x) in its `LC_LOAD_DYLIB` commands,
and real Snow Leopard hardware crashes at launch on that mismatch — this
bit us during testing (see git log for "authentic SDK + ld64" fixes). The
SDK and linker only come from one place: Apple's own Xcode 3.2.6, the last
Xcode release built for Snow Leopard.

## 1. Get Xcode 3.2.6

Apple still serves old Xcode installers to registered developers at
[developer.apple.com/download/more](https://developer.apple.com/download/more/)
(search "Xcode 3.2.6"). It ships as `xcode_3.2.6_and_ios_sdk_4.3.dmg`.

## 2. Extract the SDK and the linker

You do not need to install Xcode 3.2.6 as your primary IDE — you only need
two things out of it: the `MacOSX10.6.sdk` folder, and the `ld` binary
(ld64-97.17).

```bash
hdiutil attach xcode_3.2.6_and_ios_sdk_4.3.dmg -nobrowse

# SDK - lives inside the MacOSX10.6.pkg component package
pkgutil --expand-full "/Volumes/Xcode and iOS SDK/Packages/MacOSX10.6.pkg" /tmp/sdk106
mkdir -p Toolchain/SDKs
cp -R /tmp/sdk106/Payload/SDKs/MacOSX10.6.sdk Toolchain/SDKs/MacOSX10.6.sdk

# Linker - lives inside DeveloperToolsCLI.pkg (the command-line tools
# component), not DeveloperTools.pkg
pkgutil --expand-full "/Volumes/Xcode and iOS SDK/Packages/DeveloperToolsCLI.pkg" /tmp/clitools
mkdir -p Toolchain/bin
cp /tmp/clitools/Payload/usr/bin/ld Toolchain/bin/ld-legacy
chmod +x Toolchain/bin/ld-legacy

hdiutil detach "/Volumes/Xcode and iOS SDK"
rm -rf /tmp/sdk106 /tmp/clitools
```

Verify the linker actually runs (it's an old x86_64/i386 binary — on Apple
Silicon this executes fine under Rosetta 2, unlike a lot of other 2011-era
binaries, since it predates modern code-signing enforcement entirely and
carries no signature to trip over):

```bash
Toolchain/bin/ld-legacy -v
# @(#)PROGRAM:ld  PROJECT:ld64-97.17
```

Both `Toolchain/SDKs/` and `Toolchain/bin/` are gitignored on purpose — this
is Apple's proprietary property extracted from a licensed Xcode
installation; redistributing it is not allowed under the Xcode SLA, so
every builder pulls it from their own Xcode 3.2.6 installer. **Never commit
anything under `Toolchain/`** (a prior version of this repo accidentally
did — the whole git history was rewritten to purge it; don't repeat that).

## 3. Build

```bash
git clone https://github.com/SonyPan82/iTube-10.6.git
cd iTube-10.6

# (Steps 1-2 above, to populate Toolchain/SDKs and Toolchain/bin)

./Scripts/build-legacy-ffmpeg.sh   # ffmpeg/ffprobe, works on Apple Silicon too
./Scripts/build-legacy-python.sh   # Python 3.11 + OpenSSL - MUST run on real Intel
                                    # hardware (or an Intel CI runner) - see the
                                    # comment header in that script for why
./vendor.sh                        # fetch yt-dlp (latest) + CA cert bundle
./Scripts/build-legacy-app.sh      # compile + link the app itself, real SDK/ld

open build/iTube_legacy.app
```

`Scripts/build-legacy-app.sh` is the one that needs the real SDK + linker
from steps 1-2. The other three scripts (ffmpeg, Python, vendor.sh) work
with just a modern Xcode command-line toolchain — `build-legacy-python.sh`
just additionally needs to run on genuine Intel silicon (see that script's
header comment: CPython's build executes the freshly-built interpreter
mid-build, and Apple Silicon's Rosetta refuses to run that under this
project's testing conditions).

All four scripts pass `-march=core2`: the oldest realistic Mac in the
10.6–10.9 range has a Core 2 Duo CPU, which lacks SSE4.2/AVX/etc. Skipping
this flag produces code that crashes with "illegal instruction" the moment
it hits an auto-vectorized loop using a newer instruction than the target
CPU actually has — this was the root cause behind a long chain of crash
reports during testing, so don't drop it "to see if it's still needed."

## Quick iteration without the legacy SDK

For UI work on a modern Mac, the same sources compile fine with the system
clang at a higher deployment target:

```bash
xcrun clang -arch x86_64 -fno-objc-arc -mmacosx-version-min=10.9 -framework Cocoa \
  -o build/iTube YTubeMP3/main.m YTubeMP3/AppDelegate.m YTubeMP3/YTDLPController.m YTubeMP3/SearchResult.m
```

Just don't ship that build — it isn't linked against the real 10.6 SDK/ld64
and isn't guaranteed to run on real Snow Leopard (in practice, it crashes
at launch on real hardware for the framework-version-mismatch reason
explained above, even though it runs fine on a modern Mac where dyld is
forward-compatible enough to paper over the mismatch).
