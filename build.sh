#!/bin/bash
# 编译 Release 二进制并打成可直接运行的 .app（ad-hoc 签名，本地自用）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="StandFifty"
BUNDLE_ID="com.mousebomb.standfifty"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> 跑测试"
swift test 2>&1 | tail -5

echo "==> 编译 Release"
swift build -c release

echo "==> 组装 $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --verbose=1 "$APP_BUNDLE"

echo "==> 完成：$APP_BUNDLE"
echo "    安装：cp -R \"$APP_BUNDLE\" /Applications/"
