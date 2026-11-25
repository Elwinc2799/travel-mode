#!/bin/bash
# Builds "Travel Mode.app" into build/. Needs Xcode or the Command Line Tools (Swift 5.10+).
#   scripts/build.sh            universal app (Apple silicon + Intel)
#   ARCHS=arm64 scripts/build.sh   Apple silicon only (faster)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
APP="build/Travel Mode.app"

arch_flags=()
for a in $ARCHS; do arch_flags+=(--arch "$a"); done

echo "Building ($ARCHS)…"
swift build -c release --product TravelMode "${arch_flags[@]}"
bin_dir="$(swift build -c release --product TravelMode "${arch_flags[@]}" --show-bin-path)"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp "$bin_dir/TravelMode" "$APP/Contents/MacOS/TravelMode"

echo "Drawing the icon…"
swift Tools/MakeIcon/icon.swift build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Travel Mode</string>
  <key>CFBundleDisplayName</key><string>Travel Mode</string>
  <key>CFBundleIdentifier</key><string>io.github.elwinc2799.travel-mode</string>
  <key>CFBundleExecutable</key><string>TravelMode</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally. Not notarized (see README).
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "Built: $APP"
lipo -info "$APP/Contents/MacOS/TravelMode"
