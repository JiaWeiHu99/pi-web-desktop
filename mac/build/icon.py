#!/usr/bin/env python3
"""Pi Web App 图标生成器（纯标准库，无需 PIL）
输出: <输出目录>/icon_*.png (iconset 格式), 用法: python3 icon.py <iconset目录>
"""
import math
import os
import struct
import sys
import zlib

SS = 2048  # 超采样渲染尺寸 (2x)
MASTER = 1024


def write_png(path, w, h, rgba):
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        c += struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        return c

    raw = bytearray()
    for y in range(h):
        row = y * w * 4
        raw.append(0)
        raw.extend(rgba[row:row + w * 4])
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def sd_segment(px, py, ax, ay, bx, by):
    """点到线段的最短距离"""
    abx, aby = bx - ax, by - ay
    apx, apy = px - ax, py - ay
    denom = abx * abx + aby * aby
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (apx * abx + apy * aby) / denom))
    cx, cy = ax + t * abx, ay + t * aby
    return math.hypot(px - cx, py - cy)


def sd_round_rect(px, py, x0, y0, x1, y1, r):
    """点到圆角矩形的 SDF"""
    qx = abs(px - (x0 + x1) / 2) - ((x1 - x0) / 2 - r)
    qy = abs(py - (y0 + y1) / 2) - ((y1 - y0) / 2 - r)
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    return math.hypot(ox, oy) + min(max(qx, qy), 0.0) - r


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def cover(px, py, color, alpha, buf, W):
    """alpha 混合叠加到缓冲"""
    if alpha <= 0:
        return
    i = (py * W + px) * 4
    a = alpha
    inv = 1.0 - a
    buf[i] = int(color[0] * 255 * a + buf[i] * inv)
    buf[i + 1] = int(color[1] * 255 * a + buf[i + 1] * inv)
    buf[i + 2] = int(color[2] * 255 * a + buf[i + 2] * inv)
    buf[i + 3] = int(255 * a + buf[i + 3] * inv)


def render_master():
    S = SS
    buf = bytearray(S * S * 4)
    TOP = (0.13, 0.42, 0.99)    # #226BFC
    BOT = (0.55, 0.20, 0.95)    # #8C33F2
    WHITE = (1.0, 1.0, 1.0)

    x0, y0, x1, y1 = 0, 0, S, S
    rad = 230 * 2

    # π 字形参数 (以 1024 坐标系定义, 渲染时 *2)
    def P(v):
        return v * 2

    stroke = P(84)
    pi_top = P(682)
    pi_bot = P(392)
    pi_lx = P(398)
    pi_rx = P(626)
    bar_l, bar_r = P(312), P(712)

    chev_l, chev_r = P(426), P(546)
    chev_top, chev_bot = P(238), P(362)
    und_y = P(298)
    und_l, und_r = P(582), P(672)
    c_stroke = P(44)

    for py in range(S):
        yy = py + 0.5
        row = py * S
        for px in range(S):
            xx = px + 0.5
            d = sd_round_rect(xx, yy, x0, y0, x1, y1, rad)
            if d > 1.5:
                continue
            # 背景渐变
            t = min(1.0, max(0.0, (xx + yy) / (2 * S)))
            col = lerp(TOP, BOT, t)
            alpha_bg = max(0.0, min(1.0, 0.5 - d))
            cover(px, py, col, alpha_bg, buf, S)

            # 白色元素: 计算最小到形状的距离
            d_pi = min(
                sd_segment(xx, yy, bar_l, pi_top, bar_r, pi_top),          # 顶部横杠
                sd_segment(xx, yy, pi_lx, pi_top, pi_lx, pi_bot),          # 左竖
                sd_segment(xx, yy, pi_rx, pi_top, pi_rx, pi_bot),          # 右竖
            )
            a_pi = max(0.0, min(1.0, (stroke / 2) - d_pi))
            if a_pi > 0:
                cover(px, py, WHITE, a_pi, buf, S)

            d_chev = min(
                sd_segment(xx, yy, chev_l, chev_top, chev_r, und_y),       # 上斜线
                sd_segment(xx, yy, chev_l, chev_bot, chev_r, und_y),       # 下斜线
                sd_segment(xx, yy, und_l, und_y, und_r, und_y),            # 下划线
            )
            a_c = max(0.0, min(1.0, (c_stroke / 2) - d_chev))
            if a_c > 0:
                cover(px, py, WHITE, a_c, buf, S)
    return buf


def downsample(buf, S, out_w, out_h):
    """box filter 降采样"""
    out = bytearray(out_w * out_h * 4)
    scale = S / out_w
    for oy in range(out_h):
        y0f = oy * scale
        y1f = y0f + scale
        ys = int(y0f)
        ye = min(int(y1f) + 1, S)
        for ox in range(out_w):
            x0f = ox * scale
            x1f = x0f + scale
            xs = int(x0f)
            xe = min(int(x1f) + 1, S)
            r = g = b = a = 0.0
            n = 0
            for yy in range(ys, ye):
                fy = min(yy + 1.0, y1f) - max(yy, y0f)
                if fy <= 0:
                    continue
                row = yy * S
                for xx in range(xs, xe):
                    fx = min(xx + 1.0, x1f) - max(xx, x0f)
                    if fx <= 0:
                        continue
                    wgt = fx * fy
                    i = (row + xx) * 4
                    r += buf[i] * wgt
                    g += buf[i + 1] * wgt
                    b += buf[i + 2] * wgt
                    a += buf[i + 3] * wgt
                    n += wgt
            if n > 0:
                oi = (oy * out_w + ox) * 4
                out[oi] = int(r / n)
                out[oi + 1] = int(g / n)
                out[oi + 2] = int(b / n)
                out[oi + 3] = int(a / n)
    return out


# ---------- 源图模式: 纯标准库 PNG 解码 + 高质量重采样 ----------
# 若存在 build/logo-source.png (官方 Pi logo), 则以其为母图缩放生成全部尺寸; 否则回退到程序化渲染。

def load_png(path):
    """纯标准库 PNG 解码 (8bit, 非隔行, 支持 RGB/RGBA/灰度/调色板), 返回 (w, h, rgba)"""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("不是 PNG 文件: %s" % path)
    pos = 8
    w = h = bitdepth = colortype = interlace = 0
    idat = bytearray()
    plte = trns = None
    while pos + 8 <= len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bitdepth, colortype, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat.extend(body)
        elif typ == b"PLTE":
            plte = body
        elif typ == b"tRNS":
            trns = body
        elif typ == b"IEND":
            break
    if bitdepth != 8 or interlace != 0:
        raise ValueError("仅支持 8bit 非隔行 PNG (bitdepth=%s interlace=%s)" % (bitdepth, interlace))
    if colortype not in (2, 3, 4, 6):
        raise ValueError("不支持的 PNG 颜色类型: %s" % colortype)

    raw = zlib.decompress(bytes(idat))
    channels = {2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    stride = w * channels
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:      # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ft == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:    # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:    # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ft != 0:
            raise ValueError("未知 PNG 滤波类型: %s" % ft)

        o = y * w * 4
        if colortype == 6:
            out[o:o + w * 4] = line
        elif colortype == 2:
            for x in range(w):
                out[o + x * 4] = line[x * 3]
                out[o + x * 4 + 1] = line[x * 3 + 1]
                out[o + x * 4 + 2] = line[x * 3 + 2]
                out[o + x * 4 + 3] = 255
        elif colortype == 4:
            for x in range(w):
                g = line[x * 2]
                out[o + x * 4] = g
                out[o + x * 4 + 1] = g
                out[o + x * 4 + 2] = g
                out[o + x * 4 + 3] = line[x * 2 + 1]
        else:            # 调色板
            for x in range(w):
                idx = line[x]
                out[o + x * 4] = plte[idx * 3]
                out[o + x * 4 + 1] = plte[idx * 3 + 1]
                out[o + x * 4 + 2] = plte[idx * 3 + 2]
                out[o + x * 4 + 3] = trns[idx] if (trns and idx < len(trns)) else 255
        prev = line
    return w, h, out


def resample(src, sw, sh, dw, dh, sharpen=0.0):
    """预乘 alpha 重采样: 缩小用面积平均(精确重叠权重), 放大用双线性。
    sharpen>1 时对 alpha 过渡带做对比拉伸, 使放大后的边缘依然清晰(适合扁平图形)。"""
    out = bytearray(dw * dh * 4)
    sx, sy = sw / dw, sh / dh
    up = sx < 1.0 or sy < 1.0
    for oy in range(dh):
        for ox in range(dw):
            i = (oy * dw + ox) * 4
            if up:
                fx = (ox + 0.5) * sx - 0.5
                fy = (oy + 0.5) * sy - 0.5
                x0 = int(math.floor(fx))
                y0 = int(math.floor(fy))
                tx, ty = fx - x0, fy - y0
                r = g = b = a = 0.0
                for yy, wy in ((y0, 1.0 - ty), (y0 + 1, ty)):
                    if wy <= 0:
                        continue
                    cy = min(max(yy, 0), sh - 1)
                    for xx, wx in ((x0, 1.0 - tx), (x0 + 1, tx)):
                        if wx <= 0:
                            continue
                        cx = min(max(xx, 0), sw - 1)
                        j = (cy * sw + cx) * 4
                        al = src[j + 3] / 255.0
                        wgt = wx * wy
                        r += src[j] * al * wgt
                        g += src[j + 1] * al * wgt
                        b += src[j + 2] * al * wgt
                        a += al * wgt
                if sharpen > 0.0 and 0.0 < a < 1.0:
                    a = min(1.0, max(0.0, 0.5 + (a - 0.5) * sharpen))
                if a > 0:
                    out[i] = int(min(255.0, r / a))
                    out[i + 1] = int(min(255.0, g / a))
                    out[i + 2] = int(min(255.0, b / a))
                out[i + 3] = int(min(255.0, a * 255))
            else:
                x0f, x1f = ox * sx, ox * sx + sx
                y0f, y1f = oy * sy, oy * sy + sy
                xs, xe = int(x0f), min(int(x1f) + 1, sw)
                ys, ye = int(y0f), min(int(y1f) + 1, sh)
                r = g = b = a = n = 0.0
                for yy in range(ys, ye):
                    fy = min(yy + 1.0, y1f) - max(float(yy), y0f)
                    if fy <= 0:
                        continue
                    row = yy * sw
                    for xx in range(xs, xe):
                        fx = min(xx + 1.0, x1f) - max(float(xx), x0f)
                        if fx <= 0:
                            continue
                        wgt = fx * fy
                        j = (row + xx) * 4
                        al = src[j + 3] / 255.0
                        r += src[j] * al * wgt
                        g += src[j + 1] * al * wgt
                        b += src[j + 2] * al * wgt
                        a += al * wgt
                        n += wgt
                if n > 0 and a > 0:
                    out[i] = int(min(255.0, r / a))
                    out[i + 1] = int(min(255.0, g / a))
                    out[i + 2] = int(min(255.0, b / a))
                    out[i + 3] = int(min(255.0, a / n * 255))
    return out


SIZES = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    default_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo-source.png")
    src_path = sys.argv[2] if len(sys.argv) > 2 else default_src

    if os.path.exists(src_path):
        sw, sh, src = load_png(src_path)
        print("使用源图 %s (%dx%d) 生成 iconset" % (src_path, sw, sh))
        for name, s in SIZES:
            print("  %s (%dx%d)" % (name, s, s))
            img = resample(src, sw, sh, s, s, sharpen=1.8) if s > max(sw, sh) else resample(src, sw, sh, s, s)
            write_png(os.path.join(out_dir, name), s, s, img)
        print("完成")
        return

    print("未找到源图 %s, 回退到程序化渲染" % src_path)
    print("渲染 2048px 主图...")
    master = render_master()
    for name, s in SIZES:
        print("  %s (%dx%d)" % (name, s, s))
        write_png(os.path.join(out_dir, name), s, s, downsample(master, SS, s, s))
    print("完成")


if __name__ == "__main__":
    main()
