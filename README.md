<p align="center">
  <img src="icon.png" width="128" height="128" alt="iTube icon">
</p>

<h1 align="center">iTube</h1>

<p align="center">
  Search YouTube and download MP3s on Mac OS X Snow Leopard through Mavericks - built natively for old Mac.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Mac%20OS%20X-blue" alt="Platform">
  <img src="https://img.shields.io/badge/macOS-10.6--10.9%20(Snow%20Leopard--Mavericks)-green" alt="macOS Version">
  <img src="https://img.shields.io/badge/architecture-Intel%20x86__64-orange" alt="Architecture">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License">
</p>

---

## Download

**[Download iTube-10.6-x86_64.zip](https://github.com/SonyPan82/iTube-10.6/releases/latest)**

> Unzip, drag to Applications, and double-click to launch.
>
> First launch on an unsigned app: right-click `iTube.app` -> **Open**, then confirm. No Gatekeeper prompt games - these old systems don't have Gatekeeper to begin with.

---

## Why

Old Macs run beautifully, but there's no YouTube client for them, and yt-dlp itself needs Python 3.10+ and constant updates to keep working against YouTube - nothing close to what Snow Leopard or Mavericks ship with. iTube bundles a from-source Python 3.11 + OpenSSL, the latest yt-dlp, and a from-source ffmpeg build, all targeting 10.6, so a Snow Leopard-Mavericks Mac can search YouTube and pull down MP3s without touching the internet for anything but the app itself. See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for how that's put together - including two very real, very old-Mac-specific gotchas (a CPU instruction-set mismatch, and a linker that quietly stamps in the wrong framework versions) that took a lot of on-hardware debugging to track down.

## Features

- **Search** - query YouTube straight from the app, results list title / channel / duration
- **Download as MP3** - select a result, pick a destination folder, convert via bundled ffmpeg + libmp3lame
- **Album art** - optional checkbox to embed the YouTube thumbnail as MP3 cover art (`--embed-thumbnail`)
- **French/English UI** - follows the system language automatically, no manual switch
- **Live progress** - download progress and status reported in real time
- **Self-contained runtime** - bundled Python 3.11, yt-dlp, and a static ffmpeg build; nothing to install on the target Mac
- **Native everything** - no Electron, no system Python dependency, just Cocoa - built without ARC or Auto Layout, and linked with the genuine period-correct SDK/linker so it actually runs on real old hardware (not just "compiles with an old deployment target")

## Compatibility

| Requirement | Minimum |
|---|---|
| **OS version** | Mac OS X 10.6 Snow Leopard through 10.9 Mavericks |
| **Architecture** | Intel x86_64 (64-bit) |
| **CPU** | Core 2 Duo or newer (built with `-march=core2`; older Core Duo is 32-bit only and isn't supported) |
| **Not supported** | i386-only Macs (Core Duo and earlier), PowerPC |
| **Network** | Any working internet connection (no login/account needed) |

---

## Build from source

Building the real 10.6-targeted binary needs the Mac OS X 10.6 SDK and the genuine Xcode-3.2.6-era linker (see [Docs/BUILD_LEGACY.md](Docs/BUILD_LEGACY.md) for how to extract both), placed at `Toolchain/SDKs/MacOSX10.6.sdk` and `Toolchain/bin/ld-legacy`, then:

```bash
git clone https://github.com/SonyPan82/iTube-10.6.git
cd iTube-10.6

./Scripts/build-legacy-ffmpeg.sh   # works on Apple Silicon too
./Scripts/build-legacy-python.sh   # needs real Intel hardware - see script header
./vendor.sh                        # fetches latest yt-dlp + CA cert bundle
./Scripts/build-legacy-app.sh      # compiles + links the app with the real SDK/ld

open build/iTube_legacy.app
```

For quick UI iteration on a modern Mac without the legacy toolchain (same source, higher deployment target, modern linker - **do not ship this build**, see [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for why it won't run on real Snow Leopard despite working fine locally):

```bash
xcrun clang -arch x86_64 -fno-objc-arc -mmacosx-version-min=10.9 -framework Cocoa \
  -o build/iTube YTubeMP3/main.m YTubeMP3/AppDelegate.m YTubeMP3/YTDLPController.m YTubeMP3/SearchResult.m
```

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for how the project is put together.

---

## License

MIT - see [LICENSE](LICENSE) for details.

iTube bundles third-party components under their own licenses: [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense), [Python](https://www.python.org) (PSF License), and [FFmpeg](https://ffmpeg.org) built with `libmp3lame` (LGPL) - no GPL-only components are enabled in this build.
