# Building the real 10.6-targeted binary

iTube's release binary is compiled against the Mac OS X 10.6 SDK so it links
against nothing newer than what Snow Leopard actually shipped. That SDK only
comes from one place: Apple's own Xcode 3.2.6, the last Xcode release built
for Snow Leopard.

## 1. Get Xcode 3.2.6

Apple still serves old Xcode installers to registered developers at
[developer.apple.com/download/more](https://developer.apple.com/download/more/)
(search "Xcode 3.2.6"). It ships as `xcode_3.2.6_and_ios_sdk_4.3.dmg`.

## 2. Extract the SDK

You do not need to install Xcode 3.2.6 as your primary IDE — you only need
the `MacOSX10.6.sdk` folder out of it:

```bash
hdiutil attach xcode_3.2.6_and_ios_sdk_4.3.dmg
# The installer payload is a set of flat .pkg files; expand the one
# containing the SDK (name varies by installer revision — inspect with
# pkgutil --payload-files on each candidate under Volumes/Xcode and Tools/).
pkgutil --expand-full "/Volumes/Xcode and iOS SDK/Packages/MacOSX10.6.pkg" /tmp/sdk106
cp -R /tmp/sdk106/Payload/Developer/SDKs/MacOSX10.6.sdk Toolchain/SDKs/MacOSX10.6.sdk
hdiutil detach "/Volumes/Xcode and iOS SDK"
```

`Toolchain/SDKs/` is gitignored on purpose — the SDK is Apple's proprietary
property, redistributing it is not allowed, so every builder pulls it from
their own Xcode 3.2.6 installer.

## 3. Build

```bash
git clone https://github.com/<you>/iTube-10.6.git
cd iTube-10.6
./vendor.sh                 # fetch/build yt-dlp, ffmpeg, Python 3.6 into Tools/
./Scripts/build-legacy.sh    # compiles against Toolchain/SDKs/MacOSX10.6.sdk
open build/legacy/iTube.app
```

If `Scripts/build-legacy.sh` isn't present yet in your checkout, the manual
Xcode 3.2.6 project steps (creating the project, adding the sources, setting
Base SDK / Deployment Target to 10.6, disabling ARC) are the fallback — see
the source file headers in `YTubeMP3/` for the constraints that make the code
compatible with that toolchain (no ARC, no Auto Layout, no `.xib`, no
`NSJSONSerialization`).

## Quick iteration without the legacy SDK

For UI work on a modern Mac, the same sources compile fine with the system
clang at a higher deployment target (see the top-level build commands used
for local sanity checks) — just don't ship that build, it isn't linked
against the 10.6 SDK and isn't guaranteed to run on real Snow Leopard.
