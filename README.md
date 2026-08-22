# Pi Web Desktop — Windows 桌面客户端

> **本项目是 [agegr/pi-web](https://github.com/agegr/pi-web) 的 Windows 桌面封装版。**
> 上游 pi-web 为 [pi coding agent](https://github.com/earendil-works/pi) 提供本地浏览器界面,
> 本项目的价值在于把它变成**双击即用的 Windows 桌面应用**,无需安装 Node.js、无需敲命令行。

![Pi Web 界面](https://raw.githubusercontent.com/agegr/pi-web/main/docs/screenshot2.png)

## 快速使用

### 推荐:安装版(双击 setup.exe)

从 [Releases](https://github.com/JiaWeiHu99/pi-web-desktop/releases) 下载 `PiWeb-*-setup.exe`,双击后:

1. 出现安装向导,点 **下一步 → 安装**
2. 完成后桌面/开始菜单生成 **Pi Web** 快捷方式
3. 之后每次启动都是秒开

### 绿色免安装版(zip 解压即用)

下载 `PiWeb-*-win.zip`,解压后直接双击 `Pi Web.exe` 即可,免安装、启动秒开。

### 常见问题:双击后"没反应"

1. **先看任务栏/系统托盘** —— 应用可能已经在运行(单实例锁会让重复启动直接退出)
2. 如果仍然不行,打开任务管理器确认没有残留的 `Pi Web` 进程,再重试
3. 服务日志在 `%APPDATA%\pi-web-desktop\pi-web-server.log`,可用来排查

### 从源码构建

```bash
# 1. 克隆后安装依赖(自动触发 server/ 内部依赖安装)
npm install

# 2. 开发模式启动
npm start

# 3. 打包(NSIS 安装版 + zip 绿色版)
npm run dist
```

## 功能

- **内嵌服务**: 启动时自动拉起 pi-web 服务(默认 `127.0.0.1:30141`)并打开桌面窗口
- **托盘驻留**: 关窗最小化到托盘,服务继续运行(会话不中断);托盘菜单可重新打开/退出
- **单实例**: 重复启动只会聚焦已有窗口
- **端口自适应**: 30141 空闲用默认端口;被其他 pi-web 实例占用则复用;否则自动换空闲端口
- **外部链接**: 用系统默认浏览器打开
- **优雅退出**: 托盘退出时自动停止内置服务进程

## 目录结构

```text
pi-web-desktop/
├── main.js            Electron 主进程(服务拉起/窗口/托盘/生命周期)
├── package.json       应用配置 + electron-builder 打包配置
├── .npmrc             国内镜像配置(npmmirror)
├── build/icon.ico     应用图标(256/64/48/32/16 多尺寸)
├── server/            pi-web 服务本体(上游 npm 包 @agegr/pi-web 解包, 含预构建产物)
├── scripts/           开发辅助脚本(图标生成/打包/进程管理/截图)
├── .github/workflows/ GitHub Actions 自动打包(打 tag 即自动构建发布)
└── dist/              打包产物(不入库)
```

## 开发

| 命令 | 作用 |
| --- | --- |
| `npm start` | 开发模式启动(服务目录默认 `./server`) |
| `npm run dist` | 打包 NSIS 安装版 + zip 绿色版 |
| `npm run dist:zip` | 仅打 zip 绿色版 |
| `npm run dist:nsis` | 仅打安装版 |

### 环境变量

| 变量 | 作用 |
| --- | --- |
| `PI_WEB_SERVER_DIR` | 指定 pi-web 服务目录(默认 `./server`) |
| `ELECTRON_BUILDER_BINARIES_MIRROR` | 打包工具下载镜像(国内: `https://npmmirror.com/mirrors/electron-builder-binaries/`) |

### 自动化发布

推送形如 `v1.0.0` 的 tag 时,GitHub Actions 会自动构建 Windows 包并发布到 Releases:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

## 说明

- **国内网络**: 依赖安装与打包工具下载均已配置 npmmirror 镜像
- **服务日志**: `%APPDATA%\pi-web-desktop\pi-web-server.log`
- **安全**: 服务仅监听 `127.0.0.1`,不暴露到局域网
- **截图**: 仓库内 `docs/screenshot-local.png` 为本地实拍(未提交,自行审阅后可加入)
- **许可证**: MIT(上游 pi-web 同为 MIT,见 [LICENSE](./LICENSE))
