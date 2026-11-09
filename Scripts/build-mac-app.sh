#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$root_dir/dist/MP4 to OGV.app"
binary_dir="$app_dir/Contents/MacOS"
resources_dir="$app_dir/Contents/Resources"
release_dir="$root_dir/dist/release"

cd "$root_dir"
./Scripts/fetch-ffmpeg-runtime.sh
swift build -c release --arch arm64 --arch x86_64
binary_path="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MP4ToOGV"
rm -rf "$app_dir"
mkdir -p "$binary_dir" "$resources_dir/FFmpeg" "$release_dir"
cp "$binary_path" "$binary_dir/MP4ToOGV"
cp Assets/MP4ToOGV.icns "$resources_dir/MP4ToOGV.icns"
cp ThirdParty/FFmpeg/ffmpeg "$resources_dir/FFmpeg/ffmpeg"
chmod 755 "$resources_dir/FFmpeg/ffmpeg"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MP4ToOGV</string>
  <key>CFBundleIdentifier</key><string>dev.bootpack.mp4-to-ogv</string>
  <key>CFBundleName</key><string>MP4 to OGV</string>
  <key>CFBundleIconFile</key><string>MP4ToOGV.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

hdiutil create -quiet -volname "MP4 to OGV" -srcfolder "$app_dir" -ov -format UDZO "$release_dir/MP4-to-OGV-1.0.dmg"

echo "Built app: $app_dir"
echo "Built DMG: $release_dir/MP4-to-OGV-1.0.dmg"
