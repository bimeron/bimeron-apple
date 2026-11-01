#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/dist/Bimeron.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/Bimeron "$CONTENTS/MacOS/Bimeron"
cp -R .build/release/Bimeron_BimeronApp.bundle "$CONTENTS/Resources/"
cp Sources/BimeronApp/Resources/Brand/bimeron.icns "$CONTENTS/Resources/bimeron.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>org.bimeron.apple.dev</string>
  <key>CFBundleName</key><string>Bimeron</string>
  <key>CFBundleDisplayName</key><string>Bimeron</string>
  <key>CFBundleExecutable</key><string>Bimeron</string>
  <key>CFBundleIconFile</key><string>bimeron</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
touch "$APP"
echo "$APP"
