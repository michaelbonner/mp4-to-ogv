# Bundled FFmpeg runtime

This application includes a universal `ffmpeg` executable built by combining
the Apple Silicon and Intel static binaries from
[FFmpegBin 9.0.2](https://github.com/Tyrrrz/FFmpegBin/releases/tag/9.0.2).
`Scripts/fetch-ffmpeg-runtime.sh` fetches and checksums that executable during
the local build; the binary itself is intentionally not committed to Git.

- Upstream project: [FFmpeg](https://ffmpeg.org/)
- Binary source release: `ffmpeg-osx-arm64.zip` and `ffmpeg-osx-x64.zip`
- SHA-256 of the combined universal executable:
  `aec2e5469571c0e4c7280db77958eaa0584ecf29e5ec91fe93ccb2a392366ebb`
- FFmpeg license information and corresponding source:
  <https://ffmpeg.org/legal.html>

The bundled runtime includes GPL-enabled codecs. Anyone redistributing this
application must comply with the applicable FFmpeg and codec licenses, including
providing the corresponding-source information required by those licenses.
