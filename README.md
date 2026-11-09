# MP4 → OGV + thumbnails

This repository contains the original browser converter and a native macOS app.

## macOS app

The native app is written in SwiftUI. It converts a batch of MP4 files to OGV
(Theora/Vorbis) and creates a JPEG thumbnail from the first frame of each video.
It writes both files straight to the output folder you select.

The shipped app bundle includes a universal FFmpeg runtime (Apple Silicon and
Intel), so testers do not need Homebrew or any other prerequisite. It produces
Theora/Vorbis OGV files. The development build can still use a local `ffmpeg`
installation when launched with `swift run`.

Run it from Xcode by opening `Package.swift`, or from Terminal:

```sh
swift run MP4ToOGV
```

Build a universal app bundle and shareable DMG with:

```sh
./Scripts/build-mac-app.sh
open "dist/MP4 to OGV.app"
```

Share `dist/release/MP4-to-OGV-1.0.dmg` with testers. This build is unsigned;
they may need to approve it in System Settings → Privacy & Security. To release
it publicly, sign every executable with a Developer ID certificate, enable the
Hardened Runtime, then notarize the final DMG. Once a Developer ID identity and
`notarytool` keychain profile exist, run:

```sh
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='mp4-to-ogv-notary' \
./Scripts/sign-and-notarize.sh
```

The generated app is intentionally unsigned for local use. Sign and notarize it
before distributing outside your team.

The app icon source lives at `Assets/MP4ToOGV-icon.png`; its macOS-ready
`Assets/MP4ToOGV.icns` counterpart is copied into every built app bundle.

## Bundled FFmpeg

`ThirdParty/FFmpeg/ffmpeg` is a universal FFmpeg 9.0.2 binary assembled from
the arm64 and x64 static builds published by FFmpegBin. It is included under
FFmpeg's GPL licensing terms; see `ThirdParty/FFmpeg/NOTICE.md` before
redistributing the app.

## Browser converter

The existing Vite app runs the conversion in the browser:

```sh
bun install
bun run dev
```
