# Pi Web Desktop — pi-web 的桌面客户端 (Windows / macOS)

> **本项目是 [agegr/pi-web](https://github.com/agegr/pi-web) 的桌面封装版。**
> 上游 pi-web 为 [pi coding agent](https://github.com/earendil-works/pi) 提供本地浏览器界面,
> 本项目的价值在于把它变成**双击即用的桌面应用**,无需敲命令行。
> 两个平台各有实现:Windows 走 Electron(`main.js`,服务随包内置),macOS 走原生 Objective-C + WebKit(见 [`mac/`](./mac))。

![Pi Web 界面](https://raw.githubusercontent.com/agegr/pi-web/main/docs/screenshot2.png)

## 平台支持

| 平台 | 实现 | 发布产物 | 需要自备 Node? | 服务来源 |
| --- | --- | --- | --- | --- |
| **Windows** | Electron + electron-builder | `PiWeb-*-setup.exe`(NSIS)/ `PiWeb-*-win.zip` | 不需要 | 随包内置(`server/`,用 Electron 以 Node 模式运行) |
| **macOS** | 原生 Objective-C + WKWebView | `PiWeb-*-macos.zip`(内含 `Pi Web.app`) | 需要 ≥ 22.19 | 首次启动在线拉取到 `~/.pi-web`(约 950MB),之后本地秒起 + 静默增量更新 |

- 两端都:启动时自动拉起 pi-web 服务(`127.0.0.1:30141`)、外部链接交系统浏览器打开、退出时优雅结束服务进程。
- Windows 版**托盘驻留**(关窗不退出、会话不中断);macOS 版**关窗即退出**并回收整个服务进程组。
- macOS 版更详细的能力说明、工作原理与排障见 [`mac/README.md`](./mac/README.md)。

## Windows 版

### 快速使用

#### 推荐:安装版(双击 setup.exe)

从 [Releases](https://github.com/JiaWeiHu99/pi-web-desktop/releases) 下载 `PiWeb-*-setup.exe`,双击后:

1. 出现安装向导,点 **下一步 → 安装**
2. 完成后桌面/开始菜单生成 **Pi Web** 快捷方式
3. 之后每次启动都是秒开

#### 绿色免安装版(zip 解压即用)

下载 `PiWeb-*-win.zip`,解压后直接双击 `Pi Web.exe` 即可,免安装、启动秒开。

#### 常见问题:双击后"没反应"

1. **先看任务栏/系统托盘** —— 应用可能已经在运行(单实例锁会让重复启动直接退出)
2. 如果仍然不行,打开任务管理器确认没有残留的 `Pi Web` 进程,再重试
3. 服务日志在 `%APPDATA%\pi-web-desktop\pi-web-server.log`,可用来排查

#### 从源码构建

```bash
# 1. 克隆后安装依赖(自动触发 server/ 内部依赖安装)
npm install

# 2. 开发模式启动
npm start

# 3. 打包(NSIS 安装版 + zip 绿色版)
npm run dist
```

### 功能

- **内嵌服务**: 启动时自动拉起 pi-web 服务(默认 `127.0.0.1:30141`)并打开桌面窗口
- **托盘驻留**: 关窗最小化到托盘,服务继续运行(会话不中断);托盘菜单可重新打开/退出
- **单实例**: 重复启动只会聚焦已有窗口
- **端口自适应**: 30141 空闲用默认端口;被其他 pi-web 实例占用则复用;否则自动换空闲端口
- **外部链接**: 用系统默认浏览器打开
- **优雅退出**: 托盘退出时自动停止内置服务进程

### 开发

| 命令 | 作用 |
| --- | --- |
| `npm start` | 开发模式启动(服务目录默认 `./server`) |
| `npm run dist` | 打包 NSIS 安装版 + zip 绿色版 |
| `npm run dist:zip` | 仅打 zip 绿色版 |
| `npm run dist:nsis` | 仅打安装版 |

#### 环境变量

| 变量 | 作用 |
| --- | --- |
| `PI_WEB_SERVER_DIR` | 指定 pi-web 服务目录(默认 `./server`) |
| `ELECTRON_BUILDER_BINARIES_MIRROR` | 打包工具下载镜像(国内: `https://npmmirror.com/mirrors/electron-builder-binaries/`) |

## macOS 版

原生 macOS 客户端(Objective-C + 系统 WebKit),不需要终端、不需要浏览器:

从 [Releases](https://github.com/JiaWeiHu99/pi-web-desktop/releases) 下载 `PiWeb-*-macos.zip`,解压后:

```bash
xattr -dr com.apple.quarantine "Pi Web.app"   # 去掉下载隔离属性(或直接右键 →「打开」)
open "Pi Web.app"                              # 或双击;也可 cp 到 /Applications
```

- **前置要求**: macOS 12+,且需自备 Node.js ≥ 22.19(客户端用它跑服务与在线安装/更新)
- **首次启动较慢**: 会把完整 pi-web 安装拉到 `~/.pi-web`(约 950MB~1GB),之后每次启动秒开
- **自动更新**: 启动后后台静默对比远端版本,有新版先增量装到暂存树 `~/.pi-web.new`(老服务照常跑),再原子切换,停机约 1 秒

从源码构建:

```bash
cd mac
./build.sh                 # 按本机架构构建(需要 clang + python3 + iconutil + codesign)
UNIVERSAL=1 ./build.sh     # arm64 + x86_64 通用二进制
ZIP=1 ./build.sh           # 额外产出 dist/PiWeb-<版本>-macos.zip
./install.sh               # 安装到 /Applications
```

目录结构、`WKWebView` 能力补齐(上传/下载/原生弹框)、运行时文件与疑难排查:**[`mac/README.md`](./mac/README.md)**

## 目录结构

```text
pi-web-desktop/
├── main.js            Electron 主进程(服务拉起/窗口/托盘/生命周期)
├── package.json       应用配置 + electron-builder 打包配置(Windows)
├── .npmrc             国内镜像配置(npmmirror)
├── build/icon.ico     应用图标(256/64/48/32/16 多尺寸)
├── server/            pi-web 服务本体(上游 npm 包 @agegr/pi-web 解包, 含预构建产物)
├── scripts/           开发辅助脚本(图标生成/打包/进程管理/截图)
├── mac/               macOS 原生客户端(源码 + build.sh + install.sh + 说明)
├── .github/workflows/ GitHub Actions 自动打包(打 tag 即自动构建发布 win + mac)
└── dist/              打包产物(不入库)
```

## 自动化发布

推送形如 `v1.0.0` 的 tag 时,GitHub Actions 会自动构建 **Windows 与 macOS 两个平台**的包并发布到 Releases:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

| 工作流 | 运行环境 | 产物 |
| --- | --- | --- |
| `.github/workflows/build.yml` | `windows-latest` | `PiWeb-<版本>-setup.exe`、`PiWeb-<版本>-win.zip` |
| `.github/workflows/build-macos.yml` | `macos-latest` | `PiWeb-<版本>-macos.zip` |

### 版本号规则

**Release tag 是两个平台唯一的版本真源**，不用手改任何文件里的版本号：

- `v1.0.0` → 两端产物均为 `1.0.0`：`PiWeb-1.0.0-setup.exe` / `PiWeb-1.0.0-win.zip` / `PiWeb-1.0.0-macos.zip`
- Windows：工作流在 `npm ci` 之后用 `npm version <tag> --no-git-tag-version` 覆盖，electron-builder 据此命名（仓库内 `package.json` 的 `0.1.0` 只是本地开发默认值）
- macOS：工作流把 tag 传给 `mac/build.sh` 的 `VERSION`，覆盖 App 内的 `CFBundleShortVersionString`/`CFBundleVersion`
- 手动触发（非 tag）时两端都用 `0.0.0-dev`；本地构建 mac 时不传 `VERSION` 则跟随仓库根 `package.json`

## 说明

- **国内网络**: 依赖安装与打包工具下载均已配置 npmmirror 镜像
- **服务日志**: Windows `%APPDATA%\pi-web-desktop\pi-web-server.log`;macOS `~/.pi-web/server.log`(客户端诊断 `/tmp/piweb-diag.txt`)
- **安全**: 服务仅监听 `127.0.0.1`,不暴露到局域网
- **截图**: 仓库内 `docs/screenshot-local.png` 为本地实拍(未提交,自行审阅后可加入)
- **许可证**: MIT(上游 pi-web 同为 MIT,见 [LICENSE](./LICENSE))
