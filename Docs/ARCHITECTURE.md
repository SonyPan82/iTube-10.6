# Architecture

## The compatibility problem

yt-dlp requires Python 3.10+, and its extraction logic has to keep up with
YouTube's own changes — a version pinned too long simply stops working
("The following content is not available on this app.. Watch on the latest
version of YouTube."), typically within months. ffmpeg's official builds
target current macOS. None of this exists pre-built for Snow Leopard
through Mavericks, so iTube vendors its entire runtime from source:

- **Python 3.11.9 + OpenSSL 3.0**, both compiled from source (not the
  python.org installer — that only ever supported 10.6+ up to Python 3.6,
  which is too old for any current yt-dlp) with `-mmacosx-version-min=10.6`
  and linked against the *real* Mac OS X 10.6 SDK using the genuine ld64
  linker from Xcode 3.2.6 (see [BUILD_LEGACY.md](BUILD_LEGACY.md) and
  `Scripts/build-legacy-python.sh`). This **must run on real Intel
  hardware** (a GitHub Actions `macos-15-intel` runner in CI): CPython's
  build forks the freshly-built interpreter mid-build to generate its own
  sysconfig data, and Apple Silicon's Rosetta 2 refuses to execute that —
  not a sandboxing quirk, a real translated-code security policy with no
  viable local workaround short of a paid Developer ID certificate.
- **yt-dlp**, `vendor.sh` always fetches the *latest* release — re-run it
  periodically, an old pin will eventually break against YouTube.
- **ffmpeg + ffprobe**, statically linked and compiled from source with
  `-mmacosx-version-min=10.6`, `libmp3lame` for MP3 encoding, ffmpeg's
  built-in AAC/Opus/Vorbis decoders (no external decode libraries needed —
  YouTube's own streams), plus `webp`/`png`/`mjpeg` decode+encode and the
  `image2` demuxer/muxer for embedding YouTube thumbnails as MP3 album art.
  Apple's VideoToolbox/AudioToolbox/AVFoundation hardware-acceleration
  paths are disabled at configure time since their headers require 10.7+.

### Two hard-won gotchas, both from building on a machine that isn't the target

- **`-march=core2` everywhere.** The oldest realistic Mac in the 10.6–10.9
  range has a Core 2 Duo CPU (no SSE4.2, no AVX). Compiling without this
  flag — the default on any modern build machine — produces code that
  crashes with a bare `EXC_BAD_ACCESS`/`SIGSEGV` (or, run from a terminal
  where you can actually see it, "Illegal instruction") the instant it
  hits an auto-vectorized loop using an instruction the real CPU doesn't
  have. This was the actual root cause behind a long chain of confusing,
  identical-looking crash reports during testing — the crash address
  never moved because it wasn't about linking or signing at all.
- **No CI-machine-only dependencies.** GitHub Actions' Intel runners ship
  Homebrew with `gettext` pre-installed; CPython's `configure` happily
  auto-detects and links against `/usr/local/opt/gettext/lib/libintl.8.dylib`
  for the `_locale` module if you let it — a path that will never exist on
  the target Mac. `build-legacy-python.sh` explicitly disables that
  detection (`ac_cv_lib_intl_textdomain=no`, `ac_cv_header_libintl_h=no`)
  and strips `/usr/local` from `PATH` before `./configure` runs.

### No code signature, on purpose

The shipped app and every bundled binary (Python, ffmpeg, ffprobe) are
built **unsigned**, or explicitly stripped of any signature that gets
added along the way (`codesign --remove-signature`). Snow Leopard predates
Gatekeeper entirely and never checks signatures at launch — but a modern
`codesign`'s default ad-hoc signature uses a `CodeDirectory` format (SHA-256
hashes) that old dyld/the kernel don't understand, and can cause exactly
the kind of crash this section opened with. When in doubt, less signature
metadata is safer than more, for a target this old.

## Why no ARC, no Auto Layout, no `.xib`, no JSON parsing

The app is compiled against the real Mac OS X 10.6 SDK (via Xcode 3.2.6 —
see [BUILD_LEGACY.md](BUILD_LEGACY.md)), which predates several Cocoa
staples:

| Feature | Introduced | Workaround here |
|---|---|---|
| ARC | Xcode 4.2 / 10.7 runtime | Manual `retain`/`release`/`autorelease` throughout |
| Auto Layout (`NSLayoutConstraint`) | 10.7 | Fixed frames + `autoresizingMask` (springs & struts) |
| `NSJSONSerialization` | 10.7 | yt-dlp invoked with `--print` and a custom field separator (`\x1f`) instead of `--dump-json` — no JSON parser needed at all |
| Reliable `.xib` compatibility across Xcode versions | — | Entire UI built programmatically in `AppDelegate.m`, no nib in the bundle |

## Process model

`YTDLPController` wraps yt-dlp as an `NSTask` (spawning the bundled Python
interpreter with the yt-dlp script as its first argument). Output is read
with `NSFileHandleReadCompletionNotification` + `readInBackgroundAndNotify`
— the pre-10.7, notification-based `NSFileHandle` API — rather than the
newer block-based `readabilityHandler`. Search results come back as
`\x1f`-delimited lines; downloads report progress the same way and resolve
their final on-disk path via yt-dlp's `--print after_move:...` hook rather
than parsing `[download]` progress text.
