#!/bin/zsh
set -euo pipefail

# Required environment variables:
#   DEVELOPER_ID_APPLICATION  e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE            a keychain profile created with `xcrun notarytool store-credentials`

: "${DEVELOPER_ID_APPLICATION:?Set your Developer ID Application signing identity.}"
: "${NOTARY_PROFILE:?Set your notarytool keychain profile name.}"

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$root_dir/dist/MP4 to OGV.app"
dmg_path="$root_dir/dist/release/MP4-to-OGV-1.0.dmg"
app_binary="$app_dir/Contents/MacOS/MP4ToOGV"
ffmpeg_binary="$app_dir/Contents/Resources/FFmpeg/ffmpeg"

[[ -d "$app_dir" && -f "$dmg_path" ]] || {
  echo "Build the distributable first: ./Scripts/build-mac-app.sh" >&2
  exit 1
}

codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$ffmpeg_binary"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app_binary"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"

hdiutil create -quiet -volname "MP4 to OGV" -srcfolder "$app_dir" -ov -format UDZO "$dmg_path"
xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg_path"
spctl -a -vvv -t open "$app_dir"

echo "Signed and notarized: $dmg_path"
