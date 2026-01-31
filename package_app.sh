#!/bin/bash

# Define paths relative to the project root
PROJECT_ROOT="/Users/abeynicholas/Desktop/2026-Gravity"
APP_NAME="Gravity"
DEST_PATH="$HOME/Desktop/$APP_NAME.app"
BINARY_SOURCE="$PROJECT_ROOT/gui/.build/release/GravityRename"
ICON_PNG="$PROJECT_ROOT/app_icon_dark.png"

echo "🚀 Polishing Gravity App (@BLPRK)..."

# 1. Ensure the App structure exists
mkdir -p "$DEST_PATH/Contents/MacOS"
mkdir -p "$DEST_PATH/Contents/Resources"

# 2. Copy binary
if [ -f "$BINARY_SOURCE" ]; then
    cp "$BINARY_SOURCE" "$DEST_PATH/Contents/MacOS/Gravity"
    chmod +x "$DEST_PATH/Contents/MacOS/Gravity"
    # Copy CLI as well
    cp "$PROJECT_ROOT/gui/GravityRename/gravity-cli" "$DEST_PATH/Contents/Resources/gravity-cli"
    chmod +x "$DEST_PATH/Contents/Resources/gravity-cli"
else
    echo "❌ Error: Binary not found. Run 'swift build -c release' first."
    exit 1
fi

# 3. Create High-Resolution Icon (.icns)
if [ -f "$ICON_PNG" ]; then
    echo "🎨 Building professional dark-mode icon set..."
    ICONSET="Gravity.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    
    # Generate all required PNG sizes (Strict sizing and naming)
    sips -s format png -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null 2>&1
    sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null 2>&1
    sips -s format png -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null 2>&1
    sips -s format png -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null 2>&1
    sips -s format png -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null 2>&1
    sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1
    sips -s format png -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null 2>&1
    sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1
    sips -s format png -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null 2>&1
    sips -s format png -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1
    
    # Convert set to professional .icns file
    iconutil -c icns "$ICONSET" -o "$DEST_PATH/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "⚠️ Warning: app_icon_dark.png not found."
fi

# 4. Create/Update Info.plist
cat > "$DEST_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Gravity</string>
    <key>CFBundleIdentifier</key>
    <string>com.gravity.rename</string>
    <key>CFBundleName</key>
    <string>Gravity</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 5. Clear Icon Cache
touch "$DEST_PATH"
/usr/bin/qlmanage -r >/dev/null 2>&1 || true

# 6. Create Distribution Zip
echo "📦 Creating distribution package..."
cd ~/Desktop
rm -f Gravity_macOS.zip
zip -r Gravity_macOS.zip Gravity.app > /dev/null

echo "------------------------------------------------"
echo "✅ SUCCESS: Gravity App is now fully branded!"
echo "------------------------------------------------"
echo "📍 App Location: Desktop/Gravity.app"
echo "📦 Distributable: Desktop/Gravity_macOS.zip"
echo "👤 Team: @BLPRK"
echo "------------------------------------------------"
