// 注入到 Pi Web 页面
// 只拦截「完整历史」按钮 -> 交给原生用系统浏览器打开导出地址
// 其他按钮（生成标题/系统/工具等）一律放行，保持 pi-web 原生行为
(function () {
  function findSid() {
    // 1) URL pathname（会话详情页形如 /session/<id>）
    var m = location.pathname.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
    if (m) return m[0];

    // 2) localStorage 映射：每个工作区最后打开的会话 id
    try {
      var raw = localStorage.getItem("pi-web:last-open-by-workspace");
      if (raw) {
        var map = JSON.parse(raw);
        var keys = Object.keys(map);
        var pageText = document.body.innerText || "";
        for (var i = 0; i < keys.length; i++) {
          var wkey = keys[i];
          var base = wkey.replace(/^.*\//, "");
          if (pageText.indexOf(wkey) >= 0 || pageText.indexOf(base) >= 0) {
            return map[wkey];
          }
        }
        if (keys.length === 1) return map[keys[0]];
        return map[keys[keys.length - 1]];
      }
    } catch (e) {}

    // 3) DOM data 属性
    var d = document.querySelectorAll("[data-session-id],[data-session]");
    for (var j = 0; j < d.length; j++) {
      var v = d[j].getAttribute("data-session-id") || d[j].getAttribute("data-session");
      if (v && /^[0-9a-f-]{36}$/.test(v)) return v;
    }
    return "";
  }

  document.addEventListener(
    "click",
    function (ev) {
      var el = ev.target;
      if (!el || typeof el.closest !== "function") return;

      // 只拦截：文本精确为「完整历史」的按钮
      var b = el.closest("button,[role=button],[role=tab],[data-testid]");
      if (b && (b.textContent || "").trim() === "完整历史") {
        ev.preventDefault();
        ev.stopPropagation();
        var id = findSid();
        var u = "/api/sessions/" + id + "/export?inline=1";
        try {
          window.webkit.messageHandlers.__diag.postMessage({
            t: "openurl",
            a: u,
            dbg: "btn=完整历史 sid=" + id + " path=" + location.pathname,
          });
        } catch (e) {}
        return;
      }
      // 其余按钮放行（生成标题/系统/工具等走原生）
    },
    true
  );

  try {
    window.webkit.messageHandlers.__diag.postMessage({
      t: "info",
      a: "inject-ok path=" + location.pathname,
    });
  } catch (e) {}
})();
