# Pi Web 客户端 (macOS)

一个原生 macOS 桌面客户端，让你**不用敲命令、不用开终端、不用开浏览器**——双击打开就是 pi-web 的完整交互界面。

- 上游项目: https://github.com/agegr/pi-web
- 同仓库另有 **Windows 版**（Electron 封装，见 [仓库根目录说明](../README.md)）
- 本目录 = macOS 版：原生 Objective-C + WebKit，构建产物是一个 `.app`

## 使用

1. 双击 **`Pi Web.app`**（或运行 `./install.sh` 装到 `/Applications`，之后从启动台/Dock 启动）
2. 原生窗口直接显示 pi-web 界面（基于系统 WebKit，渲染效果与 Safari 一致）
3. 关闭窗口或 `Cmd+Q` 退出时，pi-web 服务**自动随之停止**，不留后台进程

窗口工具栏提供两个按钮：**刷新**（重新加载；若当前不是 pi-web 界面则回首页）和 **浏览器打开**（在默认浏览器中打开同一界面）。

**链接行为**：客户端窗口只用于 pi-web 界面。
- 点击界面里的**外部链接**（文档、GitHub 等）会在系统浏览器打开
- 点击 **「完整历史」** 按钮会用系统浏览器打开当前会话的导出页（`/api/sessions/<id>/export?inline=1`）
- **「生成标题」「系统」「工具」等其他按钮保持 pi-web 原生功能不变**

**文件能力**（WKWebView 不像浏览器那样自带，均已在客户端里实现）：
- **上传**：文件面板 ↑ 按钮、聊天框「附图」都会弹出系统文件选择框（多选、目录随页面要求）
- **下载**：文件条目的下载图标、mermaid 图的 SVG、工具输出「view full output」等 → 存到 `~/Downloads`（重名自动加 ` (1)`），完成后在 Finder 里选中该文件；**不会把界面顶成 PDF**
- **预览**：点击文件行在 pi-web 自己的面板里预览（PDF 用 `<iframe>` + 系统 PDF 渲染，图片/视频/docx 同理）
- JS 的 `alert` / `confirm` / `prompt` 均正常弹原生对话框

### 客户端自动做的事情
| 时机 | 行为 |
| --- | --- |
| 双击启动 | 直接运行本地安装 `~/.pi-web` 里的服务（`node …/pi-web.js --no-open`），**不联网、秒起**；首次运行时自动安装（见下） |
| 服务已在运行 | 直接连接，不重复启动 |
| 退出客户端 | 自动终止整个服务进程组，释放端口 |
| 检查更新 | 启动成功后后台静默对比远端版本（离线/源不通则跳过），发现新版先**增量装到暂存树 `~/.pi-web.new`**（此时老服务照常跑，会话不受影响），装好后**停服 → 原子切换 → 重启，停机约 1 秒** |

### 首次安装
首次启动时客户端会把完整安装放到 `~/.pi-web`（pi-web 自带 pi-coding-agent，完整安装约 **950MB~1GB**）：

- **在线安装**：直接从 npm registry 拉取 `@agegr/pi-web@latest`，源自动选择可用 registry（见工作原理），首次较慢属正常。
- 本目录是**唯一的**运行时安装位置，不再保留 npx 缓存等本地副本。

## 前置要求
- macOS 12+（`LSMinimumSystemVersion` / 构建目标均为 12.0）
- Node.js ≥ 22.19.0（检查: `node --version`）—— 运行服务与在线安装/更新都用它
  > 与 Windows 版不同，macOS 版不自带 Node，服务也不是随包内置的：首次启动会在线拉取完整安装到 `~/.pi-web`。

## 目录结构
```
mac/
├── Pi Web.app/          # 成品客户端（构建产物，不入库；双击即用）
├── build.sh             # 一键构建（改代码/图标后运行）
├── install.sh           # 安装到 /Applications
└── build/
    ├── client.m         # 客户端源码（Objective-C + WebKit）
    ├── icon.py          # 程序化图标生成器（纯 Python 标准库）
    ├── logo-source.png  # 图标母图（有则缩放生成，无则程序化渲染）
    ├── Info.plist       # App 配置
    ├── AppIcon.icns     # 图标
    └── AppIcon.iconset/ # 中间产物（构建时重新生成）
```

## 构建
```bash
cd mac
./build.sh                 # 按本机架构构建，需要 clang + python3 + iconutil + codesign（macOS 自带/CLT）
UNIVERSAL=1 ./build.sh     # arm64 + x86_64 通用二进制（CI 用这个）
ZIP=1 ./build.sh           # 额外产出 dist/PiWeb-<版本>-macos.zip
VERSION=1.2.3 ./build.sh   # 覆盖 App 版本号(CI 传 Release tag;不传时跟随仓库根 package.json)

# 开发自测: 在沙箱目录里演练「暂存安装 → 原子切换」(不弹窗/不起服务/不碰 ~/.pi-web)
"Pi Web.app/Contents/MacOS/Pi Web" --selftest-swap /tmp/sandbox/.pi-web @agegr/pi-web@latest
```

## 工作原理
- 客户端把 pi-web 完整安装维护在 `~/.pi-web`，启动时用 `posix_spawn` 跑 `bash -lc 'exec node …/node_modules/@agegr/pi-web/bin/pi-web.js --no-open'`，并把服务放进**独立进程组**；退出时对整个进程组发 SIGTERM（必要时 SIGKILL 兜底），pi-web 拉起的 pi-coding-agent 子进程也不会残留
- **启动秒起、不阻塞**：安装与更新都在线拉到 `~/.pi-web`，双击只做“直接 node 运行本地安装”，不联网、秒起——避免早期“每次启动都 npx @latest”在慢网络/registry 切换时重下 950MB 整树而超时误报失败
- **后台静默更新 + 即时生效**：服务加载成功后 ~15s，后台依次探测「npm 配置的 registry → registry.npmjs.org → registry.npmmirror.com」的 TCP:443 连通性，选可达源查远端版本；有新版则**两阶段更新**，同一会话只检查一次：
  1. **暂存安装**：先 `cp -c` 写时克隆当前安装（APFS clonefile，秒级、几乎不额外占空间）到 `~/.pi-web.new`，再 `npm install` 只做增量。这一步全程不碰正在服务的 `~/.pi-web`，**慢更新期间会话照常可用**（以前就地 npm install 会把正在运行的服务模块路径抽掉，导致 `Error: Cannot find module …/pi-ai/dist/api/openai-completions.js` 这类懒加载报错）。克隆失败则退化为全新安装。
  2. **原子切换**：装好并校验 `bin/pi-web.js` 存在后，才停服 → `mv` 两次（毫秒级）完成替换 → 重启服务。切换失败一律保留旧树继续服务；旧树 `~/.pi-web.old` 由后台删除。
- 服务进程的 cwd 固定为 `$HOME`（不是包目录）：pi-web 拉起的子进程（如扩展的 `npm install`）会继承 cwd，落包目录里就会写进正在被换掉的旧树
- 启动时顺带清理 npm 中断安装留下的回收站目录（`node_modules/@scope/.<包名>-XXXXXXXX`，只删同名正式包已不存在的）与残留的 `.new`/`.old`，避免积占几百 MB
- **不自作主张打断外部服务**：若 30141 上的 pi-web 是你在终端手动跑的（非本客户端拉起），客户端跳过自动更新，只做提示，以免就地换树把它弄坏
- 轮询端口 `30141` 就绪后，用 `WKWebView` 加载 `http://127.0.0.1:30141`
- **WKWebView 能力补齐**（浏览器自带、但它交给宿主做的事）：`runOpenPanelWithParameters:`（上传选择框）、`WKDownloadDelegate`（下载落 `~/Downloads`，并阻止 `/api/**` 资源把整个 SPA 顶掉）、`alert/confirm/prompt` 原生弹框、站内 `target=_blank` 改为本窗口打开；非 SPA 文档跳过注入脚本（`build/intercept.js` 只拦「完整历史」按钮）；刷新按钮在“当前不是 SPA”时回首页
- 启动前检测端口：已占用则直接连接已有服务（适合你已经在终端手动跑着 pi-web 的情况）
- App 为 ad-hoc 本地签名，无需开发者证书；如遇 Gatekeeper 拦截，右键 →「打开」

运行时文件：
- `~/.pi-web/` — pi-web 完整安装（含 server.log / install.log）；`~/.pi-web.new`/`~/.pi-web.old` 是更新暂存树与旧树，正常情况自动清理
- `/tmp/piweb-diag.txt` — 客户端诊断日志（`INST`/`LAUNCH`/`REG`/`UPD`/`SELFTEST` 行；界面交互看 `OPENPANEL`/`DOWNLOAD`/`JSALERT`/`JSCONFIRM`/`NAV` 行）

## 疑难排查
| 现象 | 处理 |
| --- | --- |
| 双击没反应 | 终端里运行 `open "Pi Web.app"` 看报错；确认 Node ≥ 22.19 |
| 提示启动失败 | 先看 `/tmp/piweb-diag.txt`：`INST` 行是安装/迁移记录，`LAUNCH` 后看 `~/.pi-web/server.log` 的服务日志；install 问题看 `~/.pi-web/install.log` |
| 界面报 `Error: HTTP 500` | 多半是安装不完整（如依赖被中断）。删 `~/.pi-web` 后重新打开 App 会自动在线重装；或手动 `npm install @agegr/pi-web@latest --prefix ~/.pi-web --registry=https://registry.npmjs.org/` |
| 报 `Error: Cannot find module …/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js` 之类 | 老版本客户端的已知问题：更新时**就地** `npm install`，正在跑的服务被抽走了模块路径（懒加载模块首用时才炸）。升级到本版客户端后不再出现；已碰到时按上一行重装一次即可 |
| 更新完仍是旧版本 | 若 30141 上的服务不是客户端拉起的（终端手动跑的），客户端会跳过自动更新（`UPD 服务非本客户端拉起`）。手动跑的服务请自行重启 |
| 界面里某个按钮「点了没反应」 | 先看日志到底层为何：`grep -a "OPENPANEL\|DOWNLOAD\|JSALERT\|JSCONFIRM\|NAV" /tmp/piweb-diag.txt \| tail`。没任何行 = 点击没进到原生层；有 `OPENPANEL`/`DOWNLOAD` 行 = 原生已处理（下载在 `~/Downloads`）。注意：**改完源码必须退出 App 再启动**，`open` 对已运行的实例只是激活窗口，不会换二进制 |
| 窗口一直转圈 | 首次安装/在线安装较慢（950MB 级），等待即可；仍失败则看系统日志 `log show --predicate 'process == "Pi Web"'` |
| 需要换端口 | 改 `build/client.m` 里的 `kServerPort`/`kServerURL`，再跑 `./build.sh` |
| 想同时用浏览器 | 点工具栏「浏览器打开」即可，两边共用同一服务 |
| 想强制重新安装/清空重来 | `rm -rf ~/.pi-web` 后重新打开 App 即自动重建 |
| 从 GitHub Release 下载的 zip 解压后打不开 | 被加了隔离属性：`xattr -dr com.apple.quarantine "/Applications/Pi Web.app"`，或右键 →「打开」 |
