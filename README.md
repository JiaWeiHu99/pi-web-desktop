# Pi Web Desktop — Windows 桌面客户端

基于 [agegr/pi-web](https://github.com/agegr/pi-web) 的 Windows 桌面应用封装。
内置 pi-web 服务(Next.js),双击即可启动,无需手动安装 Node.js 或运行命令行。

## 快速使用

### 直接运行(已打包)

```
dist/PiWeb-0.1.0-portable.exe   免安装单文件,双击即用
dist/PiWeb-0.1.0-setup.exe      NSIS 安装版(可自选安装目录)
```

- 首次启动需 1-3 分钟解压内置运行时(视磁盘速度),之后秒开
- 数据与 pi 终端版完全互通(会话、模型配置都在 `~/.pi/agent`)

## 功能

- **内嵌服务**: 启动时自动拉起 pi-web 服务(默认 `127.0.0.1:30141`)并打开桌面窗口
- **托盘驻留**: 关窗最小化到托盘,服务继续运行(会话不中断);托盘菜单可重新打开/退出
- **单实例**: 重复启动只会聚焦已有窗口
- **端口自适应**: 30141 空闲用默认端口;被其他 pi-web 实例占用则复用;否则自动换空闲端口
- **外部链接**: 用系统默认浏览器打开
- **优雅退出**: 托盘退出时自动停止内置服务进程

## 从源码构建

```bash
# 1. 克隆后安装依赖(自动触发 server/ 内部依赖安装)
npm install

# 2. 开发模式启动
npm start

# 3. 打包(portable + NSIS)
npm run dist
```

### 环境变量

| 变量 | 作用 |
| --- | --- |
| `PI_WEB_SERVER_DIR` | 指定 pi-web 服务目录(默认 `./server`) |
| `ELECTRON_BUILDER_BINARIES_MIRROR` | 打包工具下载镜像(国内: `https://npmmirror.com/mirrors/electron-builder-binaries/`) |

## 目录结构

```text
pi-web-desktop/
├── main.js            Electron 主进程(服务拉起/窗口/托盘/生命周期)
├── package.json       应用配置 + electron-builder 打包配置
├── .npmrc             国内镜像配置(npmmirror)
├── build/icon.ico     应用图标(256/64/48/32/16 多尺寸)
├── server/            pi-web 服务本体(上游 npm 包 @agegr/pi-web 解包)
│   ├── bin/           服务启动器
│   ├── .next/         官方预构建产物
│   ├── public/        静态资源
│   └── package.json   服务依赖清单
├── scripts/           开发辅助脚本(图标生成/打包/进程管理)
└── dist/              打包产物(不入库)
```

## 说明

- **国内网络**: 依赖安装与打包工具下载均已配置 npmmirror 镜像
- **服务日志**: `%APPDATA%\pi-web-desktop\pi-web-server.log`
- **安全**: 服务仅监听 `127.0.0.1`,不暴露到局域网
- **许可证**: MIT(上游 pi-web 同为 MIT,见 LICENSE)
