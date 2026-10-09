// ============================================================
//  Pi Web 客户端 (原生 macOS, Objective-C + WebKit)
//  双击打开即为 pi-web 交互界面，后台自动管理 pi-web 服务
//  编译: clang -fobjc-arc -O2 client.m -o "Pi Web" \
//        -framework Cocoa -framework WebKit
// ============================================================
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <spawn.h>
#import <signal.h>
#import <unistd.h>
#import <netdb.h>
#import <fcntl.h>
#import <sys/select.h>
#import <sys/time.h>
#import <sys/wait.h>
#import <errno.h>

// posix_spawn 需要的外部环境变量
#include <crt_externs.h>
#define environ (*_NSGetEnviron())

static NSString *const kServerURL = @"http://127.0.0.1:30141";
static const int kServerPort = 30141;
static const int kMaxWaitTries = 240;   // 240 * 0.5s = 120s
static pid_t gServerPid = 0;            // 我们启动的服务进程组 ID

static void write_diag(NSString *line);   // 前置声明 (实现见下方)

// ---------- 端口就绪检测 ----------
static BOOL port_ready(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kServerPort);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    close(fd);
    return rc == 0;
}

// ---------- npm registry 自动选择 (仅供安装/更新时联网使用) ----------
// 背景: 安装/升级 pi-web 需要联网访问 npm registry。
// 若 npm 配置的镜像源(如 registry.npmmirror.com 的某个 CDN 节点)当前网络连不通,
// npm 会长时间卡在 TCP 连接上导致超时。
// 策略: 依次探测[用户配置的 registry -> npmjs 官方源 -> npmmirror 镜像],
//       选第一个 TCP:443 可达的, 通过 --registry 显式指定(只对本进程生效)。
// 注: 日常启动走本地安装(~/.pi-web)直接 node 启动, 完全不依赖网络。

// TCP:443 可达性探测 (getaddrinfo + 非阻塞 connect)
static BOOL host_reachable(NSString *host, int timeoutSecs) {
    const char *hn = host.UTF8String;
    if (!hn || !*hn) return NO;
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(hn, "443", &hints, &res) != 0) return NO;
    BOOL ok = NO;
    for (struct addrinfo *ai = res; ai && !ok; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (rc == 0) {
            ok = YES;
        } else if (errno == EINPROGRESS) {
            fd_set wfds; FD_ZERO(&wfds); FD_SET(fd, &wfds);
            struct timeval tv; tv.tv_sec = timeoutSecs; tv.tv_usec = 0;
            rc = select(fd + 1, NULL, &wfds, NULL, &tv);
            if (rc > 0) {
                int soerr = 0; socklen_t slen = sizeof(soerr);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen) == 0 && soerr == 0) ok = YES;
            }
        }
        close(fd);
    }
    freeaddrinfo(res);
    return ok;
}

// 选出可用的 registry URL; 全部不可达返回 nil (保持原样, 交给 npm/缓存)
static NSString *pick_registry_url(void) {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    // 1) 用户 npm 配置的 registry (~/.npmrc / 环境), 尊重用户自选
    FILE *fp = popen("npm config get registry 2>/dev/null", "r");
    if (fp) {
        char buf[1024]; size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
        int st = pclose(fp);
        if (n > 0 && st == 0) {
            buf[n] = '\0';
            NSString *s = [[NSString stringWithUTF8String:buf]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([s hasPrefix:@"http"]) [candidates addObject:s];
        }
    }
    // 2) 兜底: 官方源 + 国内镜像
    [candidates addObject:@"https://registry.npmjs.org/"];
    [candidates addObject:@"https://registry.npmmirror.com/"];
    for (NSString *url in candidates) {
        NSURL *u = [NSURL URLWithString:url];
        if (!u.host) continue;
        write_diag([NSString stringWithFormat:@"REG 探测 %@ (%@)...", url, u.host]);
        if (host_reachable(u.host, 2)) {
            write_diag([NSString stringWithFormat:@"REG 选用 %@", url]);
            return url;
        }
        write_diag([NSString stringWithFormat:@"REG 不可达: %@", url]);
    }
    write_diag(@"REG 所有源均不可达(离线), 跳过联网操作");
    return nil;
}

// ---------- 本地安装管理 (~/.pi-web) ----------
// pi-web 会拉起 pi-coding-agent, 完整安装高达 ~950MB。为避免每次启动都走 npx @latest
// (联网查版本 + registry 切换时 npm 重下整树) 导致慢网络下超时误报失败,
// 现将完整安装固定在 ~/.pi-web: 首次/更新一律**在线** npm install 到 `@latest`,
// 双击启动直接 node 运行本地安装(秒起、不阻塞), 更新在后台进行、完成即重启生效。
// 本目录是唯一的运行时安装位置(不再依赖/保留 npx 缓存副本)。

// 运行时安装位置。PI_WEB_INSTALL_DIR 只用于开发自测(见 main 的 --selftest-swap)
static NSString *install_dir(void) {
    const char *ov = getenv("PI_WEB_INSTALL_DIR");
    if (ov && *ov) return [NSString stringWithUTF8String:ov];
    return [NSHomeDirectory() stringByAppendingPathComponent:@".pi-web"];
}
// 暂存树: 新版本先完整装到这里, 装好才切换 —— 正在服务的老树全程不受影响
static NSString *staging_dir(void) {
    return [install_dir() stringByAppendingString:@".new"];
}
// 切换后暂时留存的老树 (停服后后台删除)
static NSString *previous_dir(void) {
    return [install_dir() stringByAppendingString:@".old"];
}
static NSString *bin_path_in(NSString *dir) {
    return [dir stringByAppendingPathComponent:@"node_modules/@agegr/pi-web/bin/pi-web.js"];
}
static NSString *bin_path(void) { return bin_path_in(install_dir()); }
static NSString *server_log_path(void) {
    return [install_dir() stringByAppendingPathComponent:@"server.log"];
}
// 注意: 安装日志始终写在正式目录下, 保持 README 里的排查路径不变
static NSString *install_log_path(void) {
    return [install_dir() stringByAppendingPathComponent:@"install.log"];
}
static NSString *version_in(NSString *dir) {
    NSString *pkg = [dir stringByAppendingPathComponent:@"node_modules/@agegr/pi-web/package.json"];
    NSData *data = [NSData dataWithContentsOfFile:pkg];
    if (!data) return nil;
    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return j[@"version"];
}
static BOOL install_ready(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:bin_path()];
}
static void set_path_env(void) {
    // GUI 环境 PATH 精简，补全常用路径
    setenv("PATH",
           "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
           1);
}

// 运行 shell 命令并等待 (超时强杀整个进程组); 返回退出码 (-1=超时 -2=spawn失败 -3=信号)
static int run_shell_capped(NSString *cmd, int capSecs) {
    set_path_env();
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    char *argv[] = {"/bin/bash", "-lc", (char *)cmd.UTF8String, NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    if (rc != 0) return -2;
    int waited = 0;
    for (;;) {
        int status = 0;
        pid_t w = waitpid(pid, &status, WNOHANG);
        if (w == pid) return (WIFEXITED(status)) ? WEXITSTATUS(status) : -3;
        if (waited >= capSecs * 1000) { kill(-pid, SIGKILL); return -1; }
        usleep(200 * 1000);
        waited += 200;
    }
}

// 清理 npm 中断安装留下的回收站目录 (形态: node_modules/@scope/.<pkg>-XXXXXXXX)
// 只删「哈希段正好 8 位字母数字、自身确实是个包、且同名正式包已不存在」的那种, 避免误删他人工件。
static void cleanup_npm_trash(void) {
    NSString *cmd = [NSString stringWithFormat:
        @"find '%@/node_modules' -maxdepth 2 -type d -name '.*' -print0 2>/dev/null | "
         "while IFS= read -r -d '' d; do "
           "b=${d##*/}; b=${b#.}; "
           "hash=${b##*-}; name=${b%%-*}; "
           "[ ${#hash} -eq 8 ] || continue; "
           "case \"$hash\" in *[!A-Za-z0-9]*) continue;; esac; "
           "[ -f \"$d/package.json\" ] || continue; "
           "[ -e \"$(dirname \"$d\")/$name\" ] || rm -rf \"$d\"; "
         "done", install_dir()];
    int rc = run_shell_capped(cmd, 180);
    write_diag([NSString stringWithFormat:@"INST 残留清理 rc=%d", rc]);
}

// 阶段一: 把新版本装到暂存树 ~/.pi-web.new —— 全程不碰正在服务的老树。
// 先 copy-on-write 克隆现有安装(APFS clonefile, 秒级且几乎不额外占空间), 让 npm 只做增量更新,
// 避免每次更新都重下整棵树(慢网络下确定性的超时来源); 克隆失败则退化为全新安装。
static BOOL install_to_staging(NSString *pkgSpec, int capSecs) {
    NSString *reg = pick_registry_url();
    if (!reg) { write_diag(@"INST 无可用 registry, 跳过"); return NO; }
    NSString *live = install_dir();
    NSString *stage = staging_dir();
    NSString *log = install_log_path();
    NSString *clone = [NSString stringWithFormat:
        @"mkdir -p '%@' && rm -rf '%@' && if [ -d '%@/node_modules' ]; then "
         "cp -c -R '%@' '%@' 2>/dev/null || cp -R '%@' '%@'; else mkdir -p '%@'; fi",
        live, stage, live, live, stage, live, stage, stage];
    if (run_shell_capped(clone, 600) != 0) {
        write_diag(@"INST 暂存树克隆失败, 本次不更新");
        return NO;
    }
    write_diag([NSString stringWithFormat:@"INST 暂存树就绪(COW 克隆), 增量安装 (registry=%@, spec=%@)", reg, pkgSpec]);
    NSString *cmd = [NSString stringWithFormat:
        @"npm install --no-save --no-audit --no-fund --prefix '%@' "
         "--registry='%@' %@ >'%@' 2>&1",
        stage, reg, pkgSpec, log];
    int rc = run_shell_capped(cmd, capSecs);
    write_diag([NSString stringWithFormat:@"INST 暂存安装结束 rc=%d", rc]);
    if (rc != 0 || ![[NSFileManager defaultManager] fileExistsAtPath:bin_path_in(stage)]) {
        write_diag(@"INST 暂存安装不完整, 保留旧版本继续运行");
        return NO;
    }
    // 顺手写一份与实装版本一致的干净 package.json(继承来的 ^0.9.3 之类会让 npm ls 报 invalid)
    NSString *pj = [NSString stringWithFormat:
        @"{\n  \"name\": \"pi-web-install\",\n  \"private\": true,\n"
         "  \"dependencies\": { \"@agegr/pi-web\": \"%@\" }\n}\n",
        version_in(stage) ?: @"latest"];
    [pj writeToFile:[stage stringByAppendingPathComponent:@"package.json"]
         atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return YES;
}

// 阶段二: 原子切换(两次 rename, 毫秒级)。调用方必须先停掉自己拉起的服务。
static BOOL activate_staging(void) {
    NSString *live = install_dir(), *stage = staging_dir(), *prev = previous_dir();
    if (![[NSFileManager defaultManager] fileExistsAtPath:bin_path_in(stage)]) {
        write_diag(@"INST 暂存树不完整, 不切换");
        return NO;
    }
    NSString *cmd = [NSString stringWithFormat:
        @"for f in install.log server.log; do [ -f '%@/'$f ] && cp -f '%@/'$f '%@/'$f; done; "
         "rm -rf '%@'; "
         "if [ -d '%@' ]; then mv '%@' '%@'; fi; "
         "mv '%@' '%@'",
        live, live, stage, prev, live, live, prev, stage, live];
    int rc = run_shell_capped(cmd, 120);
    BOOL ok = (rc == 0) && [[NSFileManager defaultManager] fileExistsAtPath:bin_path_in(live)];
    write_diag([NSString stringWithFormat:@"INST 原子切换 %@ (rc=%d)", ok ? @"完成" : @"失败", rc]);
    return ok;
}

// 本地已安装版本号
static NSString *installed_version(void) {
    return version_in(install_dir());
}

// 简单 semver 比较: a>b -> 1, a==b -> 0, a<b -> -1
static int cmp_versions(NSString *a, NSString *b) {
    NSArray *pa = [a componentsSeparatedByString:@"."];
    NSArray *pb = [b componentsSeparatedByString:@"."];
    NSUInteger n = (pa.count > pb.count) ? pa.count : pb.count;
    for (NSUInteger i = 0; i < n; i++) {
        int x = i < pa.count ? [pa[i] intValue] : 0;
        int y = i < pb.count ? [pb[i] intValue] : 0;
        if (x != y) return x > y ? 1 : -1;
    }
    return 0;
}

// ---------- 启动 pi-web 服务 (独立进程组, 便于整体停止) ----------
static pid_t spawn_server(void) {
    set_path_env();
    if (!install_ready()) {
        write_diag(@"INST 本地无安装, 在线安装 (首次可能较久)...");
        if (!install_to_staging(@"@agegr/pi-web@latest", 1800) || !activate_staging()) {
            write_diag(@"INST 安装失败: 无法启动服务");
            return 0;
        }
    }
    // 上次更新被中途杀掉可能留下旧树/回收站, 启动时一并收抬
    run_shell_capped([NSString stringWithFormat:@"rm -rf '%@' '%@'", previous_dir(), staging_dir()], 300);
    cleanup_npm_trash();
    write_diag([NSString stringWithFormat:@"INST 就绪 v%@, 直接 node 启动", installed_version() ?: @"?"]);
    char cmd[2048];
    // cwd 必须是中性目录: 服务及其子进程(如扩展的 npm install)会继承 cwd,
    // 若落在包目录里, 更新换树时这些安装会写进正在被删掉的旧树。
    snprintf(cmd, sizeof(cmd),
             "cd \"$HOME\" && exec node '%s' --no-open >>'%s' 2>&1",
             bin_path().UTF8String, server_log_path().UTF8String);
    char *argv[] = {"/bin/bash", "-lc", cmd, NULL};
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);  // 子进程成为进程组组长
    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    return rc == 0 ? pid : 0;
}

// 停止我们启动的服务：杀掉整个进程组 (node + pi-coding-agent 子进程全部)
static void stop_server(void) {
    if (gServerPid <= 0) return;
    kill(-gServerPid, SIGTERM);
    usleep(400 * 1000);
    if (kill(-gServerPid, 0) == 0) {
        kill(-gServerPid, SIGKILL);
    }
    gServerPid = 0;
}

// 诊断信息写入文件（统一日志在 GUI app 里不可靠）
static void write_diag(NSString *line) {
    NSString *p = @"/tmp/piweb-diag.txt";
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                  dateStyle:NSDateFormatterShortStyle
                                                  timeStyle:NSDateFormatterMediumStyle];
    NSString *out = [NSString stringWithFormat:@"[%@] %@\n", ts, line];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:p contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:p];
    }
    [fh seekToEndOfFile];
    [fh writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// ---------- App Delegate ----------
@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, NSToolbarDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSView *loadingView;
@property (nonatomic) BOOL startedServer;   // 本次会话是否由我们启动了服务
@property (nonatomic) BOOL loadedOK;        // 页面是否加载成功
- (void)applyStagedUpdate;                  // 见 scheduleBackgroundUpdateCheck 下方
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self setupMenu];
    [self setupWindow];
    [self startServiceIfNeeded];
    [self pollAndLoad];
}

// ---------- 菜单 ----------
- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Pi Web" action:NULL keyEquivalent:@""];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Pi Web"];
    [appMenu addItemWithTitle:@"关于 Pi Web" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"隐藏 Pi Web" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出 Pi Web" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"编辑" action:NULL keyEquivalent:@""];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;

    [NSApp setMainMenu:mainMenu];
}

// ---------- 窗口 + WebView ----------
- (void)setupWindow {
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 820)
                                                styleMask:(NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskMiniaturizable |
                                                           NSWindowStyleMaskResizable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"Pi Web";
    win.minSize = NSMakeSize(900, 600);
    win.releasedWhenClosed = NO;
    [win center];
    [win setFrameAutosaveName:@"PiWebWindow"];
    self.window = win;

    // 工具栏: 刷新 / 在外部浏览器打开
    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"PiWebToolbar"];
    tb.delegate = self;
    tb.displayMode = NSToolbarDisplayModeIconOnly;
    tb.allowsUserCustomization = NO;
    win.toolbar = tb;

    // WebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    // 捕获 JS console / 报错 / 所有点击，便于诊断（写入文件）
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"__diag"];
    NSString *diagJS = @"(function(){window.__diagInjected=true;var o={log:console.log,error:console.error,warn:console.warn};console.log=function(){try{window.webkit.messageHandlers.__diag.postMessage({t:'log',a:Array.from(arguments).map(String).join(' ')})}catch(e){};o.log.apply(console,arguments)};console.error=function(){try{window.webkit.messageHandlers.__diag.postMessage({t:'err',a:Array.from(arguments).map(String).join(' ')})}catch(e){};o.error.apply(console,arguments)};console.warn=function(){try{window.webkit.messageHandlers.__diag.postMessage({t:'warn',a:Array.from(arguments).map(String).join(' ')})}catch(e){};o.warn.apply(console,arguments)};window.addEventListener('error',function(e){try{window.webkit.messageHandlers.__diag.postMessage({t:'pageerr',a:String(e.message+' @ '+e.filename+':'+e.lineno)})}catch(x)});document.addEventListener('click',function(ev){var el=ev.target;var txt=(el&&(el.textContent||el.innerText||el.value||''))||'';var tag=el?el.tagName:'';var cls=(el&&el.className||'');var id=(el&&el.id||'');try{window.webkit.messageHandlers.__diag.postMessage({t:'click',a:'tag='+tag+' text='+txt.slice(0,40)+' id='+id+' class='+cls})}catch(e){}},true);})();";
    // 在 document start 和 end 都注入一份，确保生效
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:diagJS injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [ucc addUserScript:[[WKUserScript alloc] initWithSource:diagJS injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO]];
    config.userContentController = ucc;
    WKWebView *wv = [[WKWebView alloc] initWithFrame:win.contentView.bounds configuration:config];
    wv.navigationDelegate = self;
    wv.UIDelegate = self;   // <input type=file> / alert / confirm 靠它才能弹框, 不设则「点了没反应」
    wv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [win.contentView addSubview:wv];
    self.webView = wv;

    // 加载中遮罩
    NSView *lv = [[NSView alloc] initWithFrame:win.contentView.bounds];
    lv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    lv.wantsLayer = YES;
    lv.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 48, 48)];
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.controlSize = NSControlSizeRegular;
    spinner.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    [spinner setFrameOrigin:NSMakePoint((lv.bounds.size.width - 48) / 2, lv.bounds.size.height / 2 + 12)];
    [spinner startAnimation:nil];
    [lv addSubview:spinner];

    NSTextField *label = [NSTextField labelWithString:@"正在启动 Pi Web 服务…"];
    label.font = [NSFont systemFontOfSize:14];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    [label sizeToFit];
    label.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    [label setFrameOrigin:NSMakePoint((lv.bounds.size.width - label.frame.size.width) / 2,
                                      lv.bounds.size.height / 2 - 40)];
    [lv addSubview:label];

    [win.contentView addSubview:lv];
    self.loadingView = lv;

    [win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

// ---------- 服务管理 ----------
- (void)startServiceIfNeeded {
    if (port_ready()) {
        // 已有 pi-web 在运行，直接连接
        self.startedServer = NO;
        return;
    }
    gServerPid = spawn_server();
    self.startedServer = (gServerPid > 0);
    if (!self.startedServer) {
        NSLog(@"[PiWeb] 启动 pi-web 失败 (posix_spawn)");
        write_diag(@"LAUNCH spawn_server 返回 0 (安装未就绪/无法拉起)");
    } else {
        NSLog(@"[PiWeb] 已启动服务进程组 pid=%d", gServerPid);
        write_diag([NSString stringWithFormat:@"LAUNCH 服务进程组 pid=%d", gServerPid]);
    }
}

- (void)pollAndLoad {
    __weak AppDelegate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AppDelegate *self = weakSelf;
        if (!self) return;
        // 我们自己没拉起进程(安装失败)且端口本来就不通 -> 立即报错, 不干等 120s
        if (!self.startedServer && !port_ready()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showError:@"Pi Web 服务未启动（本地安装缺失或失败）。\n\n排查: /tmp/piweb-diag.txt 与 ~/.pi-web/install.log。"];
            });
            return;
        }
        int tries = 0;
        while (!port_ready() && tries < kMaxWaitTries) {
            usleep(500 * 1000);
            tries++;
            // 我们自己启动的进程挂了且端口没起来 -> 提前失败
            if (self.startedServer && gServerPid > 0 && kill(gServerPid, 0) != 0) {
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (port_ready()) {
                [self loadWebUI];
            } else {
                [self showError:@"Pi Web 服务启动失败，请检查 Node.js 环境 (需要 ≥ 22.19) 后重试。\n\n排查: /tmp/piweb-diag.txt 与 ~/.pi-web/server.log"];
            }
        });
    });
}

- (void)loadWebUI {
    NSLog(@"[PiWeb] 服务就绪，加载 %@", kServerURL);
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:kServerURL]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:60];
    [self.webView loadRequest:req];
    // 界面加载后, 后台静默检查更新 (不阻塞本会话, 有新版则安装完自动重启生效)
    [self scheduleBackgroundUpdateCheck];
}

// 后台检查 pi-web 更新: 每次会话只查一次; 离线/源不可达时直接跳过
- (void)scheduleBackgroundUpdateCheck {
    static BOOL sChecked = NO;
    if (sChecked) return;
    sChecked = YES;
    // 只更新我们自己拉起的服务: 端口上的 pi-web 若是终端里手动跑的, 换树会把它的模块路径抽掉
    BOOL ownServer = self.startedServer;
    __weak AppDelegate *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *cur = installed_version();
        if (!cur) { write_diag(@"UPD 本地版本未知, 跳过"); return; }
        NSString *reg = pick_registry_url();
        if (!reg) return;   // 全离线, 静默跳过
        NSString *tmp = @"/tmp/piweb-latest-ver.txt";
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        NSString *viewCmd = [NSString stringWithFormat:
            @"npm view @agegr/pi-web version --registry='%@' >'%@' 2>/dev/null", reg, tmp];
        if (run_shell_capped(viewCmd, 25) != 0) {
            write_diag(@"UPD 查询远端版本失败(网络?), 跳过");
            return;
        }
        NSString *latest = [[NSString stringWithContentsOfFile:tmp encoding:NSUTF8StringEncoding error:nil]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (latest.length == 0) return;
        write_diag([NSString stringWithFormat:@"UPD 本地 v%@ / 远端 v%@", cur, latest]);
        if (cmp_versions(latest, cur) <= 0) return;   // 不降级
        if (!ownServer) {
            write_diag(@"UPD 服务非本客户端拉起, 跳过自动更新(以免就地换树打断外部服务)");
            return;
        }
        write_diag([NSString stringWithFormat:@"UPD 发现新版 v%@, 后台增量安装到暂存树 (当前会话不受影响)...", latest]);
        NSString *spec = [NSString stringWithFormat:@"@agegr/pi-web@%@", latest];
        if (!install_to_staging(spec, 1500)) {
            write_diag(@"UPD 暂存安装失败(网络?), 老版本继续运行, 下轮再试");
            return;
        }
        write_diag([NSString stringWithFormat:@"UPD 暂存树已就绪 v%@, 准备停服切换",
                    version_in(staging_dir()) ?: latest]);
        AppDelegate *s = weakSelf;
        if (s) {
            dispatch_async(dispatch_get_main_queue(), ^{ [s applyStagedUpdate]; });
        }
    });
}

// 应用已就绪的暂存树: 停服 → 原子切换(毫秒级) → 重启 → 后台清旧树
// 注: 停服会中断正在跑的那一轮会话, 但停机时长从「整个 npm install(分钟级)」缩到 1 秒左右。
- (void)applyStagedUpdate {
    if (!self.startedServer) { write_diag(@"UPD 服务已非本客户端管理, 放弃切换"); return; }
    write_diag(@"UPD 停服 → 原子切换 → 重启 (停机约 1 秒)");
    stop_server();
    if (!activate_staging()) {
        write_diag(@"UPD 切换失败, 回退旧版本继续服务");
        gServerPid = spawn_server();
        self.startedServer = (gServerPid > 0);
        [self pollAndLoad];
        return;
    }
    write_diag([NSString stringWithFormat:@"UPD 已切换 v%@, 重启服务生效", installed_version() ?: @"?"]);
    cleanup_npm_trash();
    gServerPid = spawn_server();
    self.startedServer = (gServerPid > 0);
    [self pollAndLoad];
    // 旧树后台删掉(几秒, 不阻拦界面)
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *cmd = [NSString stringWithFormat:@"rm -rf '%@'", previous_dir()];
        run_shell_capped(cmd, 900);
    });
}

- (void)showError:(NSString *)message {
    NSLog(@"[PiWeb] 错误: %@", message);
    [self.loadingView removeFromSuperview];
    NSString *html = [NSString stringWithFormat:
        @"<html><body style='font-family:-apple-system,sans-serif;display:flex;align-items:center;"
         "justify-content:center;height:100vh;margin:0;background:#f5f5f7;color:#333'>"
         "<div style='text-align:center'><h2 style='margin-bottom:12px'>😕 Pi Web 无法启动</h2>"
         "<p style='color:#666;max-width:480px'>%@</p>"
         "<p style='margin-top:24px'><a href='%@' style='color:#0071e3'>手动打开 %@</a></p></div></body></html>",
        message, kServerURL, kServerURL];
    [self.webView loadHTMLString:html baseURL:nil];
}

// ---------- 工具栏 ----------
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"reload", @"external"];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"reload", @"external"];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)flag {
    if ([identifier isEqualToString:@"reload"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
        item.label = @"刷新";
        item.paletteLabel = @"刷新";
        item.image = [NSImage imageNamed:NSImageNameRefreshTemplate];
        item.target = self;
        item.action = @selector(reloadPage:);
        item.toolTip = @"重新加载页面（若当前不是 pi-web 界面，则回到首页）";
        return item;
    }
    if ([identifier isEqualToString:@"external"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
        item.label = @"浏览器打开";
        item.paletteLabel = @"浏览器打开";
        item.image = [NSImage imageNamed:NSImageNameShareTemplate];
        item.target = self;
        item.action = @selector(openExternally:);
        item.toolTip = @"在默认浏览器中打开";
        return item;
    }
    return nil;
}
- (void)openExternally:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kServerURL]];
}

// 刷新: 正常情况就是 reload；但若当前文档已经不是 SPA(例如旧版本被 /api/** 资源顶成了 PDF),
// reload 只会把那张 PDF 又刷一遍 —— 这时直接回首页, 保证永远能回到界面。
- (void)reloadPage:(id)sender {
    NSURL *cur = self.webView.URL;
    if (cur && is_local_url(cur) && is_api_url(cur)) {
        write_diag([NSString stringWithFormat:@"RELOAD 当前不是 SPA (%@), 回首页", cur.absoluteString]);
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:kServerURL]
                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                        timeoutInterval:60];
        [self.webView loadRequest:req];
        return;
    }
    [self.webView reload];
}

// ---------- WKNavigationDelegate ----------
// 是否为 pi-web 的“导出/下载”类 API 端点（返回纯文本/文件，而非 SPA 页面）——这类链接交给系统浏览器处理
static BOOL is_export_api_url(NSURL *url) {
    NSString *path = url.path ?: @"";
    return [path hasPrefix:@"/api/"] && [path containsString:@"/export"];
}

// 是否为本机 pi-web 服务地址
static BOOL is_local_url(NSURL *url) {
    if (url.scheme == nil) return NO;
    if (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"]) return NO;
    NSString *host = url.host.lowercaseString ?: @"";
    return [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"];
}

// 是否为 pi-web 的 /api/** 接口(返回文件/数据, 而非 SPA 页面)
static BOOL is_api_url(NSURL *url) {
    return [(url.path ?: @"") hasPrefix:@"/api/"];
}

// 下载目标: ~/Downloads/文件名, 重名自动加 (1)(2)...
static NSURL *unique_download_url(NSString *filename) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                  attributes:nil error:nil];
    NSString *base = filename.length ? filename : @"download";
    NSString *ext = base.pathExtension;
    NSString *stem = [base stringByDeletingPathExtension];
    NSURL *cand = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:base]];
    for (int i = 1; i < 1000 && [[NSFileManager defaultManager] fileExistsAtPath:cand.path]; i++) {
        NSString *n = ext.length ? [NSString stringWithFormat:@"%@ (%d).%@", stem, i, ext]
                                 : [NSString stringWithFormat:@"%@ (%d)", stem, i];
        cand = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:n]];
    }
    return cand;
}

// 收到页面的 JS console / 错误 / 点击 / openurl -> 写入诊断文件
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *m = (NSDictionary *)message.body;
    write_diag([NSString stringWithFormat:@"JS %@: %@", m[@"t"] ?: @"?", m[@"a"] ?: @""]);
    // openurl：用系统浏览器打开（导出/下载类地址）
    if ([m[@"t"] isEqualToString:@"openurl"]) {
        NSString *urlStr = m[@"a"];
        if (urlStr.length > 0) {
            // 记录诊断（含 sid 来源）
            write_diag([NSString stringWithFormat:@"OPENURL dbg=%@", m[@"dbg"] ?: @""]);
            if ([urlStr hasPrefix:@"/"]) {
                urlStr = [NSString stringWithFormat:@"http://127.0.0.1:%d%@", kServerPort, urlStr];
            }
            write_diag([NSString stringWithFormat:@"OPENURL 系统浏览器: %@", urlStr]);
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlStr]];
        }
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.loadedOK = YES;
    [self.loadingView removeFromSuperview];
    NSLog(@"[PiWeb] 页面加载完成");

    // 非 SPA 文档(下载页/PDF 等)里注入没意义, 只会刷 INJECT-ERR
    NSURL *cur = webView.URL;
    if (cur && (!is_local_url(cur) || is_api_url(cur))) {
        write_diag([NSString stringWithFormat:@"SKIP-INJECT 非 SPA 文档: %@", cur.absoluteString]);
        return;
    }
    write_diag(@"didFinishNavigation: 注入点击拦截...");

    // 从 bundle 读取注入脚本（避免 ObjC 字符串转义问题）
    NSString *injectPath = [[NSBundle mainBundle] pathForResource:@"intercept" ofType:@"js"];
    if (injectPath) {
        NSString *inject = [NSString stringWithContentsOfFile:injectPath encoding:NSUTF8StringEncoding error:nil];
        [webView evaluateJavaScript:inject completionHandler:^(id result, NSError *error) {
            if (error) {
                write_diag([NSString stringWithFormat:@"INJECT-ERR: %@ | msg=%@", error.localizedDescription, error.userInfo[@"WKJavaScriptExceptionMessage"] ?: @""]);
            } else {
                write_diag(@"INJECT-OK 点击拦截已注入");
            }
        }];
    } else {
        write_diag(@"INJECT-ERR: 找不到 intercept.js");
    }
}

// 用户点击的顶层链接导航：
//  - 外部域 或 导出类 API -> 交给系统浏览器（保持原行为）
//  - 下载类(<a download>) 或 直指 /api/** 的资源 -> 真下载到 ~/Downloads
//    WKWebView 本身不处理下载: 不拦的话它会直接把 PDF 之类顶掉整个 SPA, 而且刷新也救不回来。
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                        preferences:(WKWebpagePreferences *)preferences
                    decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    BOOL isMainFrame = (navigationAction.targetFrame == nil) || navigationAction.targetFrame.isMainFrame;
    if (url && isMainFrame) {
        if (is_export_api_url(url)) {
            write_diag([NSString stringWithFormat:@"NAV 导出API交系统浏览器: %@", url.absoluteString]);
            [[NSWorkspace sharedWorkspace] openURL:url];
            decisionHandler(WKNavigationActionPolicyCancel, preferences);
            return;
        }
        if (navigationAction.shouldPerformDownload || (is_local_url(url) && is_api_url(url))) {
            write_diag([NSString stringWithFormat:@"NAV 当下载处理(不顶掉界面, shouldPerformDownload=%d): %@",
                        (int)navigationAction.shouldPerformDownload, url.absoluteString]);
            decisionHandler(WKNavigationActionPolicyDownload, preferences);
            return;
        }
        if (navigationAction.navigationType == WKNavigationTypeLinkActivated && !is_local_url(url)) {
            write_diag([NSString stringWithFormat:@"NAV 外部链接交系统浏览器: %@", url.absoluteString]);
            [[NSWorkspace sharedWorkspace] openURL:url];
            decisionHandler(WKNavigationActionPolicyCancel, preferences);
            return;
        }
        write_diag([NSString stringWithFormat:@"NAV SPA 内导航放行 (type=%ld): %@",
                    (long)navigationAction.navigationType, url.absoluteString]);
    } else if (url) {
        write_diag([NSString stringWithFormat:@"NAV 子框架 type=%ld -> %@",
                    (long)navigationAction.navigationType, url.absoluteString]);
    }
    decisionHandler(WKNavigationActionPolicyAllow, preferences);
}

// ---------- 下载 (WKDownloadDelegate) ----------
// 最近一次下载目标, 仅供 didFinish/didFail 日志与 Finder 定位使用
static NSString *gLastDownloadPath = nil;

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction
                                        didBecomeDownload:(WKDownload *)download {
    download.delegate = self;
    write_diag([NSString stringWithFormat:@"DOWNLOAD 开始(navigationAction): %@",
                navigationAction.request.URL.absoluteString]);
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse
                                        didBecomeDownload:(WKDownload *)download {
    download.delegate = self;
    write_diag([NSString stringWithFormat:@"DOWNLOAD 开始(navigationResponse): %@",
                navigationResponse.response.URL.absoluteString]);
}

- (void)download:(WKDownload *)download
    decideDestinationUsingResponse:(NSURLResponse *)response
                 suggestedFilename:(NSString *)suggestedFilename
                 completionHandler:(void (^)(NSURL * _Nullable destination))completionHandler {
    NSString *name = suggestedFilename ?: @"download";
    NSString *decoded = [name stringByRemovingPercentEncoding];   // 中文文件名可能是百分号编码
    if (decoded.length > 0) name = decoded;
    NSURL *dest = unique_download_url(name);
    gLastDownloadPath = dest.path;
    write_diag([NSString stringWithFormat:@"DOWNLOAD 目标: %@", dest.path]);
    completionHandler(dest);
}

- (void)downloadDidFinish:(WKDownload *)download {
    write_diag([NSString stringWithFormat:@"DOWNLOAD 完成: %@", gLastDownloadPath ?: @"?"]);
    if (gLastDownloadPath) {
        NSURL *u = [NSURL fileURLWithPath:gLastDownloadPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:u.path]) {
            // 在 Finder 里选中, 让用户知道存到哪了
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[u]];
        }
    }
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    write_diag([NSString stringWithFormat:@"DOWNLOAD 失败: %@ (目标 %@)",
                error.localizedDescription, gLastDownloadPath ?: @"?"]);
}

// target=_blank / 新窗口链接：
//  - 外部域或导出类 API -> 在系统浏览器打开，避免窗口被带跑
//  - 本站 SPA 地址 -> 在本窗口内加载(以前是直接丢弃, 表现为点了没反应)
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
            forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    write_diag([NSString stringWithFormat:@"NAV createWebView -> %@ (local=%d api=%d export=%d)",
                url.absoluteString ?: @"nil", url ? is_local_url(url) : 0,
                url ? is_api_url(url) : 0, url ? is_export_api_url(url) : 0]);
    if (url && (!is_local_url(url) || is_export_api_url(url))) {
        write_diag([NSString stringWithFormat:@"NAV 交系统浏览器(新窗口): %@", url.absoluteString]);
        [[NSWorkspace sharedWorkspace] openURL:url];
        return nil;
    }
    if (url && is_local_url(url) && !is_api_url(url)) {
        write_diag([NSString stringWithFormat:@"NAV 新窗口请求的站内地址, 改在本窗口打开: %@", url.absoluteString]);
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

// ---------- WKUIDelegate ----------
// WKWebView 不会自己弹文件选择框: 页面里的 <input type=file>.click() 必须由宿主把 NSOpenPanel 呈上来。
// 不实现这个回调时表现就是「上传按钮点了没反应」(浏览器里能弹是因为浏览器自己实现了)。
// pi-web 的两处上传(文件面板上传、聊天附图)都走这条路径。
- (void)webView:(WKWebView *)webView
    runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
              initiatedByFrame:(WKFrameInfo *)frame
             completionHandler:(void (^)(NSArray<NSURL *> * _Nullable URLs))completionHandler {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = parameters.allowsDirectories;
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    panel.resolvesAliases = YES;
    panel.title = @"选择要上传的文件";
    panel.prompt = @"上传";
    write_diag([NSString stringWithFormat:@"OPENPANEL 弹出文件选择框 (多选=%d 目录=%d)",
                (int)parameters.allowsMultipleSelection, (int)parameters.allowsDirectories]);
    void (^finish)(NSModalResponse) = ^(NSModalResponse resp) {
        NSArray<NSURL *> *urls = (resp == NSModalResponseOK) ? panel.URLs : nil;
        write_diag([NSString stringWithFormat:@"OPENPANEL 选择结果: %lu 个", (unsigned long)urls.count]);
        completionHandler(urls);
    };
    if (self.window) [panel beginSheetModalForWindow:self.window completionHandler:finish];
    else [panel beginWithCompletionHandler:finish];
}

// 以下三个同理: WKWebView 里 alert/confirm/prompt 也必须宿主实现, 否則默认为「静默无效」
- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
    write_diag([NSString stringWithFormat:@"JSALERT %@", message]);
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Pi Web";
    a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"好"];
    if (self.window) {
        [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) { completionHandler(); }];
    } else {
        [a runModal];
        completionHandler();
    }
}

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL result))completionHandler {
    write_diag([NSString stringWithFormat:@"JSCONFIRM %@", message]);
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Pi Web";
    a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"确定"];
    [a addButtonWithTitle:@"取消"];
    if (self.window) {
        [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
            completionHandler(r == NSAlertFirstButtonReturn);
        }];
    } else {
        NSModalResponse r = [a runModal];
        completionHandler(r == NSAlertFirstButtonReturn);
    }
}

- (void)webView:(WKWebView *)webView
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                              defaultText:(NSString *)defaultText
                         initiatedByFrame:(WKFrameInfo *)frame
                        completionHandler:(void (^)(NSString * _Nullable result))completionHandler {
    write_diag([NSString stringWithFormat:@"JSPROMPT %@", prompt]);
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Pi Web";
    a.informativeText = prompt ?: @"";
    [a addButtonWithTitle:@"确定"];
    [a addButtonWithTitle:@"取消"];
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    tf.stringValue = defaultText ?: @"";
    a.accessoryView = tf;
    if (self.window) {
        [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
            completionHandler(r == NSAlertFirstButtonReturn ? tf.stringValue : nil);
        }];
    } else {
        NSModalResponse r = [a runModal];
        completionHandler(r == NSAlertFirstButtonReturn ? tf.stringValue : nil);
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    if (!self.loadedOK) {
        [self showError:[NSString stringWithFormat:@"无法连接到 pi-web 服务 (%@)。", error.localizedDescription]];
    }
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    NSLog(@"[PiWeb] 页面加载失败: %@", error.localizedDescription);
}

// ---------- 生命周期 ----------
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.startedServer) {
        NSLog(@"[PiWeb] 退出，停止服务");
        stop_server();
    }
}

@end

// ---------- 入口 ----------
int main(int argc, const char *argv[]) {
    // 开发自测(不弹窗、不起服务): 验证「暂存安装 → 原子切换」这条更新路径
    //   Pi\ Web --selftest-swap <installDir> [pkgSpec]
    if (argc >= 2 && strcmp(argv[1], "--selftest-swap") == 0) {
        @autoreleasepool {
            if (argc >= 3) setenv("PI_WEB_INSTALL_DIR", argv[2], 1);
            NSString *spec = argc >= 4 ? [NSString stringWithUTF8String:argv[3]]
                                       : @"@agegr/pi-web@latest";
            write_diag([NSString stringWithFormat:@"SELFTEST 目录=%@ spec=%@", install_dir(), spec]);
            BOOL ok = install_to_staging(spec, 1800);
            write_diag([NSString stringWithFormat:@"SELFTEST 暂存安装 %@", ok ? @"OK" : @"失败"]);
            if (ok) {
                ok = activate_staging();
                write_diag([NSString stringWithFormat:@"SELFTEST 原子切换 %@", ok ? @"OK" : @"失败"]);
                cleanup_npm_trash();
                write_diag([NSString stringWithFormat:@"SELFTEST 切换后实装版本 v%@", installed_version() ?: @"?"]);
            }
            return ok ? 0 : 1;
        }
    }
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
