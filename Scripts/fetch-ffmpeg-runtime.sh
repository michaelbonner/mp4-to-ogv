#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
runtime_dir="$root_dir/ThirdParty/FFmpeg"
runtime="$runtime_dir/ffmpeg"
expected_sha="aec2e5469571c0e4c7280db77958eaa0584ecf29e5ec91fe93ccb2a392366ebb"
tmp_dir="$(mktemp -d /tmp/mp4-to-ogv-ffmpeg.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

[[ -x "$runtime" ]] && [[ "$(shasum -a 256 "$runtime" | awk '{print $1}')" == "$expected_sha" ]] && exit 0

mkdir -p "$runtime_dir" "$tmp_dir/arm64" "$tmp_dir/x64"
curl -fL --retry 2 -o "$tmp_dir/arm64.zip" \
  https://github.com/Tyrrrz/FFmpegBin/releases/download/9.0.2/ffmpeg-osx-arm64.zip
curl -fL --retry 2 -o "$tmp_dir/x64.zip" \
  https://github.com/Tyrrrz/FFmpegBin/releases/download/9.0.2/ffmpeg-osx-x64.zip
unzip -q "$tmp_dir/arm64.zip" -d "$tmp_dir/arm64"
unzip -q "$tmp_dir/x64.zip" -d "$tmp_dir/x64"
lipo -create "$tmp_dir/arm64/ffmpeg" "$tmp_dir/x64/ffmpeg" -output "$runtime"
chmod 755 "$runtime"

actual_sha="$(shasum -a 256 "$runtime" | awk '{print $1}')"
[[ "$actual_sha" == "$expected_sha" ]] || {
  rm -f "$runtime"
  echo "FFmpeg runtime checksum did not match." >&2
  exit 1
}
