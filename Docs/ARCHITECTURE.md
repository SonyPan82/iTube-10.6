# Architecture

## The compatibility problem

yt-dlp requires Python 3.9+. ffmpeg's official builds target current macOS.
Neither exists for Snow Leopard through Mavericks. iTube works around this by
vendoring, rather than assuming, its entire runtime:

- **Python 3.6.8**, the last CPython release with an official python.org
  installer advertising Mac OS X 10.6+ support, extracted from its `.pkg`
  payload (not installed system-wide) and re-linked with `install_name_tool`
  so every dylib it loads (`libssl`, `libcrypto`, `libpython`) resolves via
  `@loader_path`/`@executable_path` relative to the app bundle instead of
  `/Library/Frameworks/...`. Without that step the interpreter looks for
  itself at an absolute path that won't exist on the target machine.
- **yt-dlp**, pinned to a release still compatible with Python 3.6 (yt-dlp
  raised its minimum past 3.6 in later versions).
- **ffmpeg + ffprobe**, statically linked and compiled from source with
  `-mmacosx-version-min=10.6`, `libmp3lame` for MP3 encoding, and ffmpeg's
  built-in AAC/Opus/Vorbis decoders (no external decode libraries needed —
  YouTube's own streams). Apple's VideoToolbox/AudioToolbox/AVFoundation
  hardware-acceleration paths are disabled at configure time since their
  headers require 10.7+.

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
