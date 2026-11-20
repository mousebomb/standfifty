#!/bin/bash
# 出可分发的 release 包：universal 二进制 → .app → 签名 → DMG → 公证 → 装订
#
# 用法：
#   ./scripts/release.sh 1.0.0                  # 正式签名 + 公证（需要 Developer ID 证书 + 公证凭据）
#   ./scripts/release.sh 1.0.0 --adhoc          # 免证书，本地验证流水线
#   ./scripts/release.sh 1.0.0 --skip-notarize  # 只签名不公证
#
# 相关环境变量：
#   SIGN_IDENTITY   签名身份，默认自动找 "Developer ID Application"
#   NOTARY_PROFILE  notarytool 的 keychain profile 名（xcrun notarytool store-credentials 建的）
#   BUILD_NUMBER    CFBundleVersion，默认用 git 提交数
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="StandFifty"
BUNDLE_ID="com.mousebomb.standfifty"
MIN_MACOS="14.0"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "用法：$0 <版本号> [--adhoc] [--skip-notarize]"
    exit 1
fi
VERSION="${VERSION#v}"   # 兼容 v1.0.0 这种 tag 形式
shift

MODE="developer-id"
SKIP_NOTARIZE=0
for arg in "$@"; do
    case "$arg" in
        --adhoc) MODE="adhoc" ;;
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        *) echo "未知参数：$arg"; exit 1 ;;
    esac
done

BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
DIST_DIR="dist"
STAGE_DIR="build/release"
DMG_STAGE="build/dmg"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> 版本 ${VERSION} (build ${BUILD_NUMBER})，模式 ${MODE}"

# ---------- 1. 测试 ----------
echo "==> 跑单元测试"
swift test 2>&1 | tail -3

# ---------- 2. 双架构编译 + lipo ----------
echo "==> 编译 arm64"
swift build -c release --triple "arm64-apple-macosx${MIN_MACOS}" 2>&1 | tail -2
echo "==> 编译 x86_64"
swift build -c release --triple "x86_64-apple-macosx${MIN_MACOS}" 2>&1 | tail -2

ARM_BIN=".build/arm64-apple-macosx/release/${APP_NAME}"
X86_BIN=".build/x86_64-apple-macosx/release/${APP_NAME}"
[ -f "$ARM_BIN" ] || { echo "找不到 arm64 产物：$ARM_BIN"; exit 1; }
[ -f "$X86_BIN" ] || { echo "找不到 x86_64 产物：$X86_BIN"; exit 1; }

# ---------- 3. 组装 .app ----------
echo "==> 组装 ${APP_BUNDLE}"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# universal 二进制：两份单架构 lipo 成一个
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# 版本号注入（Info.plist 里的默认值只是占位）
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$APP_BUNDLE/Contents/Info.plist"

lipo -info "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

# ---------- 4. 签名 ----------
if [ "$MODE" = "developer-id" ]; then
    if [ -z "${SIGN_IDENTITY:-}" ]; then
        SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
    fi
    if [ -z "${SIGN_IDENTITY:-}" ]; then
        echo "没找到 Developer ID Application 证书。"
        echo "先建证书，或用 --adhoc 跑通流水线。"
        security find-identity -v -p codesigning || true
        exit 1
    fi
    echo "==> 签名身份：${SIGN_IDENTITY}"
    # hardened runtime + 可信时间戳是公证的硬性要求
    codesign --force --options runtime --timestamp \
        --identifier "$BUNDLE_ID" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

    echo "==> 校验签名"
    codesign --verify --strict --verbose=2 "$APP_BUNDLE"
    spctl -a -vvv -t exec "$APP_BUNDLE" || echo "（公证前 spctl 报未公证属正常）"
else
    echo "==> ad-hoc 签名（不可分发，仅验证流水线）"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
    codesign --verify --strict "$APP_BUNDLE"
fi

# ---------- 5. 打 DMG ----------
echo "==> 生成 DMG"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE" "$DIST_DIR"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
# 拖拽安装用的 /Applications 快捷方式
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG_PATH"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

# ---------- 6. 公证 + 装订 ----------
if [ "$MODE" = "developer-id" ] && [ "$SKIP_NOTARIZE" -eq 0 ]; then
    if [ -z "${NOTARY_PROFILE:-}" ]; then
        echo "缺少 NOTARY_PROFILE，跳过公证。"
        echo "先执行：xcrun notarytool store-credentials <profile名> --apple-id ... --team-id ... --password ..."
    else
        echo "==> 提交公证（可能要等 1~3 分钟）"
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

        echo "==> 装订票据"
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler validate "$DMG_PATH"
        spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH"
    fi
fi

# ---------- 7. 收尾 ----------
echo "==> 产物"
ls -lh "$DMG_PATH"
echo "==> SHA256"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
echo
echo "完成：${DMG_PATH}"
