// Pi Web Desktop — Electron 主进程
// 职责: 内嵌启动 pi-web 服务(子进程), 打开窗口, 托盘驻留, 生命周期管理
"use strict";

const { app, BrowserWindow, Tray, Menu, dialog, shell, nativeImage } = require("electron");
const { spawn } = require("child_process");
const http = require("http");
const net = require("net");
const path = require("path");
const fs = require("fs");

const DEFAULT_PORT = 30141;
const APP_URL_HOST = "127.0.0.1";

// ---------------------------------------------------------------------------
// 定位 pi-web 服务目录
// ---------------------------------------------------------------------------
function resolveServerDir() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, "pi-web");
  }
  return (
    process.env.PI_WEB_SERVER_DIR ||
    path.join(__dirname, "server")
  );
}

function serverBin(serverDir) {
  return path.join(serverDir, "bin", "pi-web.js");
}

// ---------------------------------------------------------------------------
// 端口工具
// ---------------------------------------------------------------------------
function getFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.once("error", reject);
    srv.listen(0, APP_URL_HOST, () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
  });
}

function portResponds(port, timeoutMs = 1500) {
  return new Promise((resolve) => {
    const req = http.get(
      { host: APP_URL_HOST, port, path: "/", timeout: 1000 },
      (res) => {
        res.resume();
        resolve(true);
      }
    );
    req.on("error", () => resolve(false));
    req.on("timeout", () => {
      req.destroy();
      resolve(false);
    });
    setTimeout(() => {
      req.destroy();
      resolve(false);
    }, timeoutMs);
  });
}

// 端口是否空闲(未被监听)
function isPortFree(port) {
  return new Promise((resolve) => {
    const sock = net.connect({ host: APP_URL_HOST, port });
    sock.once("connect", () => {
      sock.destroy();
      resolve(false);
    });
    sock.once("error", () => resolve(true));
    setTimeout(() => {
      sock.destroy();
      resolve(true);
    }, 1500);
  });
}

// 轮询等待服务就绪
function waitForServer(port, timeoutMs = 40000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const tryOnce = () => {
      http
        .get({ host: APP_URL_HOST, port, path: "/", timeout: 2000 }, (res) => {
          res.resume();
          resolve();
        })
        .on("error", () => {
          if (Date.now() - started > timeoutMs) {
            reject(new Error(`服务启动超时 (${timeoutMs}ms)`));
          } else {
            setTimeout(tryOnce, 250);
          }
        })
        .on("timeout", function () {
          this.destroy();
        });
    };
    tryOnce();
  });
}

// ---------------------------------------------------------------------------
// 状态
// ---------------------------------------------------------------------------
let mainWindow = null;
let tray = null;
let serverProcess = null;
let serverLogStream = null;
let serverPort = DEFAULT_PORT;
let quitting = false;

function logDir() {
  return app.getPath("userData");
}

function logFile() {
  return path.join(logDir(), "pi-web-server.log");
}

// ---------------------------------------------------------------------------
// 服务生命周期
// ---------------------------------------------------------------------------
function stopServer() {
  if (!serverProcess) return;
  const child = serverProcess;
  serverProcess = null;
  try {
    child.kill(); // SIGTERM
  } catch {
    /* ignore */
  }
  // Windows 上子进程可能还挂着孙进程(next server), 兜底杀进程树
  setTimeout(() => {
    try {
      if (child.pid) {
        spawn("taskkill", ["/PID", String(child.pid), "/T", "/F"], {
          windowsHide: true,
          stdio: "ignore",
        });
      }
    } catch {
      /* ignore */
    }
  }, 1500);
}

function startServer(port) {
  return new Promise((resolve, reject) => {
    const serverDir = resolveServerDir();
    const bin = serverBin(serverDir);

    if (!fs.existsSync(bin)) {
      reject(
        new Error(
          `未找到 pi-web 服务入口: ${bin}\n请确认服务包已就位 (开发模式: ./server)`
        )
      );
      return;
    }

    try {
      serverLogStream = fs.createWriteStream(logFile(), { flags: "a" });
      serverLogStream.write(
        `\n===== ${new Date().toISOString()} 启动服务 (port=${port}) =====\n`
      );
    } catch {
      serverLogStream = null;
    }

    // ELECTRON_RUN_AS_NODE=1 让 Electron 以纯 Node 模式运行 pi-web 入口,
    // 打包后无需另外携带 node.exe
    serverProcess = spawn(
      process.execPath,
      [bin, "--no-open", "-p", String(port)],
      {
        cwd: serverDir,
        env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
      }
    );

    serverProcess.stdout.on("data", (d) => {
      if (serverLogStream) serverLogStream.write(d);
    });
    serverProcess.stderr.on("data", (d) => {
      if (serverLogStream) serverLogStream.write(d);
    });

    serverProcess.on("error", (err) => {
      reject(new Error(`服务进程启动失败: ${err.message}`));
    });

    serverProcess.on("exit", (code, signal) => {
      if (serverLogStream) {
        serverLogStream.write(
          `===== ${new Date().toISOString()} 服务退出 code=${code} signal=${signal} =====\n`
        );
      }
      serverProcess = null;
      // 非主动退出时提示
      if (!quitting && mainWindow && !mainWindow.isDestroyed()) {
        dialog.showErrorBox(
          "Pi Web 服务异常退出",
          `pi-web 服务进程已退出 (code=${code})。\n日志: ${logFile()}`
        );
      }
    });

    waitForServer(port)
      .then(() => resolve(port))
      .catch(reject);
  });
}

// ---------------------------------------------------------------------------
// 窗口
// ---------------------------------------------------------------------------
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 940,
    minHeight: 600,
    title: "Pi Web",
    icon: path.join(__dirname, "build", "icon.png"),
    autoHideMenuBar: true,
    backgroundColor: "#0b1220",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  });

  mainWindow.loadURL(`http://${APP_URL_HOST}:${serverPort}`);

  // 外部链接用系统浏览器打开
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });
  mainWindow.webContents.on("will-navigate", (e, url) => {
    if (!url.startsWith(`http://${APP_URL_HOST}:${serverPort}`)) {
      e.preventDefault();
      if (/^https?:/i.test(url)) shell.openExternal(url);
    }
  });

  // 关闭窗口 → 隐藏到托盘, 服务继续跑(会话不中断)
  mainWindow.on("close", (e) => {
    if (!quitting) {
      e.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on("closed", () => {
    mainWindow = null;
  });

  mainWindow.on("page-title-updated", (e, title) => {
    e.preventDefault();
    mainWindow.setTitle(`Pi Web — ${title}`);
  });
}

// ---------------------------------------------------------------------------
// 托盘
// ---------------------------------------------------------------------------
function createTray() {
  const iconPath = path.join(__dirname, "build", "icon.png");
  tray = new Tray(fs.existsSync(iconPath) ? iconPath : appIconFallback());
  tray.setToolTip("Pi Web");
  tray.setContextMenu(
    Menu.buildFromTemplate([
      {
        label: "打开 Pi Web",
        click: () => {
          if (!mainWindow || mainWindow.isDestroyed()) {
            createWindow();
          } else {
            mainWindow.show();
            mainWindow.focus();
          }
        },
      },
      {
        label: "在浏览器中打开",
        click: () => shell.openExternal(`http://${APP_URL_HOST}:${serverPort}`),
      },
      { type: "separator" },
      {
        label: "退出",
        click: () => {
          quitting = true;
          app.quit();
        },
      },
    ])
  );
  tray.on("click", () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.focus();
    }
  });
}

function appIconFallback() {
  // 无自定义图标时: 生成一个纯色方块作为兜底
  return nativeImage.createFromDataURL(
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFUlEQVR4nGNkYPj/n4EIwDiq0dQGAJl1Av0gZsxUAAAAAElFTkSuQmCC"
  );
}

// ---------------------------------------------------------------------------
// 应用生命周期
// ---------------------------------------------------------------------------
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.focus();
    }
  });

  app.whenReady().then(async () => {
    app.setAppUserModelId("dev.piweb.desktop");

    // 1. 端口策略: 优先默认 30141; 已被其他 pi-web 实例占用则复用; 否则换空闲端口
    try {
      if (await isPortFree(DEFAULT_PORT)) {
        serverPort = DEFAULT_PORT;
        await startServer(serverPort);
      } else if (await portResponds(DEFAULT_PORT)) {
        serverPort = DEFAULT_PORT;
      } else {
        serverPort = await getFreePort();
        await startServer(serverPort);
      }
    } catch (err) {
      dialog.showErrorBox("Pi Web 启动失败", String(err.message || err));
      app.exit(1);
      return;
    }

    createWindow();
    createTray();

    // 启动就绪后打印日志便于排查
    console.log(`[pi-web-desktop] 服务就绪: http://${APP_URL_HOST}:${serverPort}`);
  });

  app.on("before-quit", () => {
    quitting = true;
    stopServer();
  });

  app.on("window-all-closed", () => {
    // 托盘驻留模式: 不自动退出 (macOS 之外也保持)
  });

  app.on("activate", () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
    }
  });
}
