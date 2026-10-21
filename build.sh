#!/bin/bash
# 编译并打包 WorkHealth.app；传入 install 参数则安装到 ~/Applications 并启动
set -euo pipefail
cd "$(dirname "$0")"

APP=build/WorkHealth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/WorkHealth" Sources/main.swift

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WorkHealth</string>
    <key>CFBundleDisplayName</key><string>健康提醒</string>
    <key>CFBundleIdentifier</key><string>com.workhealth.healthreminder</string>
    <key>CFBundleExecutable</key><string>WorkHealth</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ 构建完成: $APP"

if [[ "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications/WorkHealth.app"
    mkdir -p "$HOME/Applications"
    pkill -x WorkHealth 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "✅ 已安装并启动: $DEST"
fi
