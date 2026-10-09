#!/bin/bash
# ============================================================
#  Pi Web mac 客户端一键构建脚本
#  用法: ./build.sh                 # 按本机架构构建
#        UNIVERSAL=1 ./build.sh     # 通用二进制 (arm64 + x86_64, CI 用)
#        ZIP=1 ./build.sh           # 额外产出 dist/PiWeb-<版本>-macos.zip
#        VERSION=1.2.3 ./build.sh   # 覆盖 App 版本号(CI 用 Release tag;不改动源码里的 Info.plist)
#  依赖: clang, python3, iconutil, codesign (macOS 自带 / CLT)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

APP="Pi Web.app"

ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS="-arch arm64 -arch x86_64"
    echo "==> 通用二进制模式 (arm64 + x86_64)"
fi

echo "==> 1/4 生成图标"
python3 build/icon.py build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "==> 2/4 编译客户端 (Objective-C + WebKit)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# shellcheck disable=SC2086  # ARCH_FLAGS 需要按空格拆成多个参数
clang -fobjc-arc -O2 -mmacosx-version-min=12.0 $ARCH_FLAGS build/client.m \
    -o "$APP/Contents/MacOS/Pi Web" \
    -framework Cocoa -framework WebKit

echo "==> 3/4 组装 App 包"
cp build/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    echo "    覆盖版本号: $VERSION"
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/intercept.js "$APP/Contents/Resources/intercept.js"
plutil -lint "$APP/Contents/Info.plist"

echo "==> 4/4 临时签名 (ad-hoc)"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

if [ "${ZIP:-0}" = "1" ]; then
    VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
    mkdir -p dist
    rm -f "dist/PiWeb-${VERSION}-macos.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/PiWeb-${VERSION}-macos.zip"
    echo "==> 已打包: $(pwd)/dist/PiWeb-${VERSION}-macos.zip"
fi

echo ""
echo "构建完成: $(pwd)/$APP"
echo "双击即为 Pi Web 客户端界面（无需终端和浏览器）"
