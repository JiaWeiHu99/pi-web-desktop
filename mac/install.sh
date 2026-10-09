#!/bin/bash
# ============================================================
#  安装 Pi Web.app 到 /Applications
#  用法: ./install.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "Pi Web.app" ]; then
    echo "未找到 Pi Web.app，请先运行 ./build.sh"
    exit 1
fi

if [ -d "/Applications/Pi Web.app" ]; then
    echo "==> 移除 /Applications 里的旧版本"
    rm -rf "/Applications/Pi Web.app"
fi

cp -R "Pi Web.app" /Applications/
echo "已安装到 /Applications/Pi Web.app"
echo "在启动台或 /Applications 中双击即可启动"
echo "（若被 Gatekeeper 拦截，右键 → 打开，或先执行 xattr -dr com.apple.quarantine \"/Applications/Pi Web.app\"）"
