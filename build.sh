#!/bin/bash
# 编译并打包 WorkHealth.app；参数 install 安装到 ~/Applications 并启动，dmg 生成安装包
# 环境变量 VERSION / BUILD_NUMBER 可指定版本号
set -euo pipefail
cd "$(dirname "$0")"

APP=build/WorkHealth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

VERSION="${VERSION:-1.0}"
BUILD="${BUILD_NUMBER:-1}"

# 同时编译 Apple 芯片和 Intel，合并为通用二进制
TMP=$(mktemp -d)
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        -o "$TMP/WorkHealth-$arch" Sources/main.swift
done
lipo -create "$TMP"/WorkHealth-* -output "$APP/Contents/MacOS/WorkHealth"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WorkHealth</string>
    <key>CFBundleDisplayName</key><string>健康提醒</string>
    <key>CFBundleIdentifier</key><string>com.workhealth.healthreminder</string>
    <key>CFBundleExecutable</key><string>WorkHealth</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ 构建完成: $APP ($VERSION)"

if [[ "${1:-}" == "dmg" ]]; then
    DMG="build/WorkHealth-$VERSION.dmg"
    STAGE=build/dmg
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname WorkHealth -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "✅ 安装包: $DMG"
fi

if [[ "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications/WorkHealth.app"
    mkdir -p "$HOME/Applications"
    pkill -x WorkHealth 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "✅ 已安装并启动: $DEST"
fi
