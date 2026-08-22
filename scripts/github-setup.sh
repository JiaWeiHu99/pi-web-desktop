#!/bin/bash
# GitHub 仓库信息设置 + Release 创建
set -e
TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
REPO="JiaWeiHu99/pi-web-desktop"
API="https://api.github.com/repos/$REPO"

# 1. 设置描述
DESC='Windows 桌面客户端 for the pi coding agent —— 基于 pi-web 的本地桌面版 (Electron 封装, 双击即用)'
curl -s -X PATCH "$API" \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d "{\"description\": \"$DESC\"}" | grep -o '"description": *"[^"]*"' | head -1

# 2. 设置 Topics
curl -s -X PUT "$API/topics" \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d '{"names":["pi-web","pi-coding-agent","electron","desktop-app","windows","ai-coding-agent","nextjs"]}' \
  | grep -o '"names": *\[[^]]*\]' | head -1

# 3. 创建 Release
RELEASE_BODY='## Pi Web Desktop v0.1.0

基于 [agegr/pi-web](https://github.com/agegr/pi-web) (MIT) 的 Windows 桌面客户端封装。

### 特性
- 内嵌 pi-web 服务, 双击即用, 无需安装 Node.js
- 系统托盘驻留, 关闭窗口服务不中断
- 与 pi 终端版共用会话与模型配置 (~/.pi/agent)
- 端口自适应, 单实例锁, 外部链接走系统浏览器

### 下载
- PiWeb-0.1.0-portable.exe — 免安装单文件版
- PiWeb-0.1.0-setup.exe — NSIS 安装版

> 上游项目 [pi-web](https://github.com/agegr/pi-web): Local browser UI for the pi coding agent'

RELEASE_JSON=$(curl -s -X POST "$API/releases" \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d "$(python -c "import json,sys; print(json.dumps({'tag_name':'v0.1.0','name':'v0.1.0','body':sys.argv[1],'draft':False,'prerelease':False}))" "$RELEASE_BODY")")
echo "$RELEASE_JSON" | grep -o '"id": *[0-9]*' | head -1
echo "$RELEASE_JSON" | grep -o '"html_url": *"[^"]*"' | head -1
