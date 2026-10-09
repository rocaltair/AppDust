#!/bin/bash
# AppDust 构建 / 安装脚本
#   ./install.sh         构建并安装到 /Applications（默认）
#   ./install.sh build   只构建，产物留在 build/DerivedData
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-install}"

command -v xcodegen >/dev/null 2>&1 || { echo "缺少 xcodegen：brew install xcodegen"; exit 1; }

echo "==> 生成 Xcode 工程 (xcodegen)"
xcodegen generate

echo "==> 构建 Release"
xcodebuild \
  -project AppDust.xcodeproj \
  -scheme AppDust \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build | tail -n 25

APP="build/DerivedData/Build/Products/Release/AppDust.app"
[ -d "$APP" ] || { echo "构建产物缺失：$APP"; exit 1; }

if [ "$MODE" = "build" ]; then
  echo "==> 构建完成：$(pwd)/$APP"
  exit 0
fi

echo "==> 安装到 /Applications"
pkill -x AppDust >/dev/null 2>&1 || true
# 清理改名前的旧版本
if [ -d /Applications/AppCleaner.app ]; then
  echo "==> 移除旧名称版本 /Applications/AppCleaner.app"
  pkill -x AppCleaner >/dev/null 2>&1 || true
  rm -rf /Applications/AppCleaner.app
fi
rm -rf /Applications/AppDust.app
cp -R "$APP" /Applications/AppDust.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/AppDust.app >/dev/null 2>&1 || true

echo "==> 完成：/Applications/AppDust.app"
open /Applications/AppDust.app
