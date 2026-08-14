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

Old Macs run beautifully, but there's no YouTube client for them and yt-dlp itself needs Python 3.9+ - nothing close to what Snow Leopard or Mavericks ship with. iTube bundles its own Python 3.6 interpreter, a compatible yt-dlp, and a from-source ffmpeg build targeting 10.6, so a Snow Leopard-Mavericks Mac can search YouTube and pull down MP3s without touching the internet for anything but the app itself. See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for how that's put together.

## Features

- **Search** - query YouTube straight from the app, results list title / channel / duration
- **Download as MP3** - select a result, pick a destination folder, convert via bundled ffmpeg + libmp3lame
- **Live progress** - download progress and status reported in real time
- **Self-contained runtime** - bundled Python 3.6, yt-dlp, and a static ffmpeg build; nothing to install on the target Mac
- **Native everything** - no Electron, no system Python dependency, just Cocoa - built without ARC or Auto Layout so it links cleanly against the real 10.6 SDK

## Compatibility

| Requirement | Minimum |
|---|---|
| **OS version** | Mac OS X 10.6 Snow Leopard through 10.9 Mavericks |
| **Architecture** | Intel x86_64 (64-bit) |
| **Not supported** | i386-only Macs (pre-2007), PowerPC |
| **Network** | Any working internet connection (no login/account needed) |

---

## Build from source

Building the real 10.6-targeted binary requires the Mac OS X 10.6 SDK (see [Docs/BUILD_LEGACY.md](Docs/BUILD_LEGACY.md) for how to obtain it) placed at `Toolchain/SDKs/MacOSX10.6.sdk`, then:

```bash
git clone https://github.com/SonyPan82/iTube-10.6.git
cd iTube-10.6
./vendor.sh
./Scripts/build-legacy.sh
open build/legacy/iTube.app
```

For quick UI iteration on a modern Mac without the legacy SDK (same source, higher deployment target for convenience):

```bash
xcrun clang -arch x86_64 -fno-objc-arc -mmacosx-version-min=10.9 -framework Cocoa \
  -o build/iTube YTubeMP3/main.m YTubeMP3/AppDelegate.m YTubeMP3/YTDLPController.m YTubeMP3/SearchResult.m
```

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for how the project is put together.

---

## License

MIT - see [LICENSE](LICENSE) for details.

iTube bundles third-party components under their own licenses: [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense), [Python](https://www.python.org) (PSF License), and [FFmpeg](https://ffmpeg.org) built with `libmp3lame` (LGPL) - no GPL-only components are enabled in this build.
