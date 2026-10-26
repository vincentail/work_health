// 生成 WorkHealth 宣传视频（1920x1080 / 30fps / H.264，配程序合成的背景音乐）
// 用法：swiftc -O promo/make_promo.swift -o build/make_promo && build/make_promo build/WorkHealth-promo.mp4 [预览图目录]
import AppKit
import AVFoundation

let W: CGFloat = 1920, H: CGFloat = 1080
let fps: Int32 = 30
let duration = 41.0
var ctx: CGContext!

// MARK: - 动画工具

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { let t = clamp(x); return t * t * (3 - 2 * t) }
func easeOutBack(_ x: Double) -> Double {
    let t = clamp(x), c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let dark = rgb(0x0f172a), gray = rgb(0x64748b), blue = rgb(0x2563eb), green = rgb(0x4ade80)

// MARK: - 绘图工具（坐标原点在左上角）

func withAlpha(_ a: Double, _ body: () -> Void) {
    guard a > 0.001 else { return }
    ctx.saveGState()
    ctx.setAlpha(a)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func scaled(_ s: Double, at c: CGPoint, _ body: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: -c.x, y: -c.y)
    body()
    ctx.restoreGState()
}

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func roundRect(_ r: CGRect, _ radius: CGFloat, fill: NSColor, shadow: Bool = false) {
    ctx.saveGState()
    if shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70,
                      color: NSColor.black.withAlphaComponent(0.4).cgColor)
    }
    ctx.addPath(roundedPath(r, radius))
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
}

func gradient(_ colors: [NSColor], in r: CGRect, clip: CGPath? = nil) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    ctx.saveGState()
    if let clip { ctx.addPath(clip); ctx.clip() }
    ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
    ctx.restoreGState()
}

func attr(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color])
}

enum Align { case left, center, right }

/// 单行文字，p 为垂直居中点
@discardableResult
func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white,
           at p: CGPoint, align: Align = .center) -> CGSize {
    let a = attr(s, size, weight, color)
    let sz = a.size()
    let x = align == .left ? p.x : align == .center ? p.x - sz.width / 2 : p.x - sz.width
    a.draw(at: CGPoint(x: x, y: p.y - sz.height / 2))
    return sz
}

/// 多行居中文字
func para(_ s: String, _ size: CGFloat, _ color: NSColor, center c: CGPoint, width: CGFloat, lineSpacing: CGFloat = 8) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.lineSpacing = lineSpacing
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size),
                                                       .foregroundColor: color, .paragraphStyle: p])
    let h = a.boundingRect(with: CGSize(width: width, height: 2000), options: .usesLineFragmentOrigin).height
    a.draw(with: CGRect(x: c.x - width / 2, y: c.y - h / 2, width: width, height: h), options: .usesLineFragmentOrigin)
}

@discardableResult
func symbol(_ name: String, size: CGFloat, color: NSColor, at p: CGPoint, align: Align = .center) -> CGSize {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    else { return .zero }
    let s = img.size
    let x = align == .left ? p.x : align == .center ? p.x - s.width / 2 : p.x - s.width
    img.draw(in: CGRect(x: x, y: p.y - s.height / 2, width: s.width, height: s.height), from: .zero,
             operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    return s
}

func appIcon(center c: CGPoint, size s: CGFloat) {
    let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
    roundRect(r, s * 0.23, fill: rgb(0x16a34a), shadow: true)
    gradient([rgb(0x4ade80), rgb(0x0ea5e9)], in: r, clip: roundedPath(r, s * 0.23))
    symbol("figure.seated.side", size: s * 0.46, color: .white, at: c)
}

// MARK: - 背景

func background(_ t: Double) {
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    gradient([rgb(0x0b1d2a), rgb(0x123a4a), rgb(0x1d5c63)], in: full)
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    for (i, c) in [rgb(0x38bdf8, 0.22), rgb(0x4ade80, 0.16)].enumerated() {
        let k = Double(i)
        let p = CGPoint(x: W * (0.25 + 0.5 * k) + 160 * sin(t * 0.35 + k * 2),
                        y: H * (0.3 + 0.4 * k) + 90 * cos(t * 0.28 + k))
        let g = CGGradient(colorsSpace: space, colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray,
                           locations: nil)!
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: 700, options: [])
    }
}

// MARK: - 模拟桌面与提醒弹窗

let desk = CGRect(x: 310, y: 90, width: 1300, height: 760)

func desktop(statusSymbol: String, statusText: String, pulse: Double) {
    roundRect(desk, 26, fill: .black, shadow: true)
    gradient([rgb(0x93c5fd), rgb(0xc4b5fd), rgb(0xf9a8d4)], in: desk, clip: roundedPath(desk, 26))

    // 菜单栏
    let bar = CGRect(x: desk.minX, y: desk.minY, width: desk.width, height: 46)
    ctx.saveGState()
    ctx.addPath(roundedPath(desk, 26)); ctx.clip()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.72).cgColor)
    ctx.fill(bar)
    ctx.restoreGState()
    let y = bar.midY
    var x = desk.minX + 30
    x += symbol("apple.logo", size: 20, color: dark, at: CGPoint(x: x, y: y), align: .left).width + 28
    x += label("Finder", 20, .bold, dark, at: CGPoint(x: x, y: y), align: .left).width + 26
    for m in ["文件", "编辑", "显示", "窗口"] {
        x += label(m, 20, .regular, dark, at: CGPoint(x: x, y: y), align: .left).width + 26
    }
    var r = desk.maxX - 28
    r -= label("周一 10:30", 20, .medium, dark, at: CGPoint(x: r, y: y), align: .right).width + 26
    r -= symbol("wifi", size: 18, color: dark, at: CGPoint(x: r, y: y), align: .right).width + 26
    r -= symbol("battery.75percent", size: 18, color: dark, at: CGPoint(x: r, y: y), align: .right).width + 22

    // 状态栏图标（本 App）
    let textW = attr(statusText, 20, .semibold, dark).size().width
    let itemW = textW + 40
    let item = CGRect(x: r - itemW - 8, y: y - 16, width: itemW + 16, height: 32)
    roundRect(item, 8, fill: rgb(0x2563eb, 0.12 + 0.25 * pulse))
    symbol(statusSymbol, size: 19, color: dark, at: CGPoint(x: item.minX + 8, y: y), align: .left)
    label(statusText, 20, .semibold, dark, at: CGPoint(x: item.maxX - 8, y: y), align: .right)
}

func promptWindow(emoji: String, title: String, message: String, buttons: [String],
                  appear: Double, vanish: Double = 0, pressed: Bool = false, windows: Bool = false) {
    let c = CGPoint(x: desk.midX, y: desk.midY + (windows ? -14 : 10))
    withAlpha(ease(appear * 1.6) * (1 - ease(vanish))) {
        scaled(0.85 + 0.15 * easeOutBack(appear), at: c) {
            let w: CGFloat = 660, h: CGFloat = 420
            let r = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            roundRect(r, windows ? 12 : 30, fill: rgb(0xf8fafc), shadow: true)
            label(emoji, 78, at: CGPoint(x: c.x, y: r.minY + 82))
            label(title, 36, .bold, dark, at: CGPoint(x: c.x, y: r.minY + 172))
            para(message, 23, gray, center: CGPoint(x: c.x, y: r.minY + 248), width: 580)

            let widths = buttons.map { attr($0, 22, .medium, dark).size().width + 60 }
            var bx = c.x - (widths.reduce(0, +) + CGFloat(buttons.count - 1) * 16) / 2
            for (i, title) in buttons.enumerated() {
                let br = CGRect(x: bx, y: r.maxY - 92, width: widths[i], height: 56)
                let primary = i == 0
                scaled(primary && pressed ? 0.94 : 1, at: CGPoint(x: br.midX, y: br.midY)) {
                    let main = windows ? rgb(0x0067c0) : blue
                    roundRect(br, windows ? 6 : 13, fill: primary ? (pressed ? rgb(0x1d4ed8) : main) : rgb(0xe2e8f0))
                    label(title, 22, .medium, primary ? .white : dark, at: CGPoint(x: br.midX, y: br.midY))
                }
                bx += widths[i] + 16
            }
        }
    }
}

func windowsLogo(at p: CGPoint, size: CGFloat, color: NSColor) {
    let g = size * 0.08, s = (size - g) / 2
    ctx.setFillColor(color.cgColor)
    for i in 0..<2 {
        for j in 0..<2 {
            ctx.fill(CGRect(x: p.x - size / 2 + CGFloat(i) * (s + g), y: p.y - size / 2 + CGFloat(j) * (s + g),
                            width: s, height: s))
        }
    }
}

/// 平台标签（画面顶部）
func platformPill(_ text: String, windows: Bool) {
    let w = attr(text, 24, .semibold, .white).size().width + 76
    let r = CGRect(x: 960 - w / 2, y: 22, width: w, height: 48)
    roundRect(r, 24, fill: NSColor.white.withAlphaComponent(0.14))
    let icon = CGPoint(x: r.minX + 32, y: r.midY)
    if windows { windowsLogo(at: icon, size: 20, color: .white) }
    else { symbol("apple.logo", size: 21, color: .white, at: icon) }
    label(text, 24, .semibold, at: CGPoint(x: r.minX + 54, y: r.midY), align: .left)
}

/// Windows 11 风格桌面，返回托盘图标位置
@discardableResult
func windowsDesktop(trayText: String, trayColor: NSColor, pulse: Double) -> CGRect {
    roundRect(desk, 18, fill: .black, shadow: true)
    gradient([rgb(0x0b2e6b), rgb(0x1565c0), rgb(0x7cc4fa)], in: desk, clip: roundedPath(desk, 18))

    let bar = CGRect(x: desk.minX, y: desk.maxY - 58, width: desk.width, height: 58)
    ctx.saveGState()
    ctx.addPath(roundedPath(desk, 18)); ctx.clip()
    ctx.setFillColor(rgb(0xf3f3f3, 0.94).cgColor)
    ctx.fill(bar)
    ctx.restoreGState()
    let y = bar.midY

    // 居中的开始按钮、搜索框和应用
    var x = desk.midX - 190
    windowsLogo(at: CGPoint(x: x, y: y), size: 24, color: rgb(0x0078d4))
    x += 30
    let search = CGRect(x: x, y: y - 18, width: 170, height: 36)
    roundRect(search, 18, fill: .white)
    symbol("magnifyingglass", size: 15, color: gray, at: CGPoint(x: search.minX + 22, y: y))
    label("搜索", 17, .regular, gray, at: CGPoint(x: search.minX + 42, y: y), align: .left)
    x = search.maxX + 36
    for (name, color) in [("folder.fill", rgb(0xf4b400)), ("globe", rgb(0x0f9d58)), ("envelope.fill", rgb(0x0078d4))] {
        symbol(name, size: 24, color: color, at: CGPoint(x: x, y: y))
        x += 56
    }

    // 右侧：时间、音量、网络、托盘图标
    var r = desk.maxX - 24
    label("10:30", 16, .regular, dark, at: CGPoint(x: r, y: y - 11), align: .right)
    r -= label("2026/10/26", 16, .regular, dark, at: CGPoint(x: r, y: y + 11), align: .right).width + 22
    r -= symbol("speaker.wave.2.fill", size: 17, color: dark, at: CGPoint(x: r, y: y), align: .right).width + 14
    r -= symbol("wifi", size: 17, color: dark, at: CGPoint(x: r, y: y), align: .right).width + 22
    let icon = CGRect(x: r - 30, y: y - 15, width: 30, height: 30)
    roundRect(icon.insetBy(dx: -7, dy: -7), 6, fill: rgb(0x000000, 0.05 + 0.15 * pulse))
    roundRect(icon, 7, fill: trayColor)
    label(trayText, trayText.count >= 3 ? 13 : 17, .bold, .white, at: CGPoint(x: icon.midX, y: icon.midY))
    symbol("chevron.up", size: 14, color: dark, at: CGPoint(x: icon.minX - 22, y: y), align: .right)
    return icon
}

/// Windows 托盘右键菜单，返回「设置」一行的位置
@discardableResult
func windowsMenu(_ items: [String], right: CGFloat, top: CGFloat? = nil, bottom: CGFloat = 0, width: CGFloat,
                 infoRows: Int = 0, hover: String?, appear: Double) -> CGRect {
    let rowH: CGFloat = 40, sepH: CGFloat = 13
    let height = items.reduce(16) { $0 + ($1 == "-" ? sepH : rowH) }
    let r = CGRect(x: right - width, y: top ?? bottom - height, width: width, height: height)
    var hovered = CGRect.zero
    withAlpha(ease(appear * 1.5)) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(1 - ease(appear)) * 16)
        roundRect(r, 10, fill: rgb(0xf9f9f9), shadow: true)
        var y = r.minY + 8
        for (i, item) in items.enumerated() {
            if item == "-" {
                ctx.setFillColor(rgb(0xe2e8f0).cgColor)
                ctx.fill(CGRect(x: r.minX + 12, y: y + sepH / 2, width: width - 24, height: 1))
                y += sepH
                continue
            }
            let row = CGRect(x: r.minX + 6, y: y, width: width - 12, height: rowH)
            if item == hover { roundRect(row, 6, fill: rgb(0x0f172a, 0.07)); hovered = row }
            let isInfo = i < infoRows
            let hasSub = item.hasSuffix("›")
            let text = hasSub ? String(item.dropLast()).trimmingCharacters(in: .whitespaces) : item
            label(text, 19, .regular, isInfo ? gray : dark, at: CGPoint(x: row.minX + 16, y: row.midY), align: .left)
            if hasSub { label("›", 22, .regular, gray, at: CGPoint(x: row.maxX - 16, y: row.midY - 2), align: .right) }
            y += rowH
        }
        ctx.restoreGState()
    }
    return hovered
}

func cups(filled: Int, fillingProgress: Double, alpha: Double) {
    withAlpha(alpha) {
        let n = 8, cw: CGFloat = 40, ch: CGFloat = 56, gap: CGFloat = 22
        let total = CGFloat(n) * cw + CGFloat(n - 1) * gap
        let panel = CGRect(x: desk.midX - total / 2 - 30, y: desk.maxY - 112, width: total + 60, height: 86)
        roundRect(panel, 22, fill: NSColor.white.withAlphaComponent(0.82))
        for i in 0..<n {
            let cr = CGRect(x: panel.minX + 30 + CGFloat(i) * (cw + gap), y: panel.midY - ch / 2, width: cw, height: ch)
            let level = i < filled ? 1 : i == filled ? ease(fillingProgress) : 0
            if level > 0 {
                let fh = (ch - 6) * level
                roundRect(CGRect(x: cr.minX + 3, y: cr.maxY - 3 - fh, width: cw - 6, height: fh), 6,
                          fill: rgb(0x38bdf8))
            }
            ctx.addPath(roundedPath(cr, 8))
            ctx.setStrokeColor(rgb(0x0ea5e9).cgColor)
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
    }
}

// MARK: - 场景

func sceneAlpha(_ t: Double, _ a: Double, _ b: Double) -> Double {
    ease(prog(t, a, a + 0.5)) * (1 - ease(prog(t, b - 0.5, b)))
}

func slideIn(_ p: Double, _ body: (CGFloat) -> Void) {
    withAlpha(ease(p)) { body(CGFloat((1 - ease(p)) * 40)) }
}

func intro(_ u: Double) {
    let s = easeOutBack(prog(u, 0.2, 0.9))
    withAlpha(ease(prog(u, 0.2, 0.6))) {
        scaled(max(s, 0.01), at: CGPoint(x: 960, y: 360)) { appIcon(center: CGPoint(x: 960, y: 360), size: 220) }
    }
    slideIn(prog(u, 0.7, 1.3)) { d in label("WorkHealth", 128, .heavy, at: CGPoint(x: 960, y: 610 + d)) }
    slideIn(prog(u, 1.1, 1.7)) { d in
        label("久坐提醒 · 喝水提醒 · 支持 macOS 与 Windows", 46, .medium, rgb(0xcbd5e1), at: CGPoint(x: 960, y: 740 + d))
    }
}

func problem(_ u: Double) {
    let lines = ["一坐就是一下午？", "颈椎酸、腰背痛？", "忙起来连水都忘了喝？"]
    for (i, s) in lines.enumerated() {
        slideIn(prog(u, 0.2 + Double(i) * 0.7, 0.7 + Double(i) * 0.7)) { d in
            label(s, 76, .bold, at: CGPoint(x: 960, y: 300 + CGFloat(i) * 130 + d))
        }
    }
    slideIn(prog(u, 2.6, 3.2)) { d in
        label("让 WorkHealth 帮你记着 👋", 64, .heavy, green, at: CGPoint(x: 960, y: 790 + d))
    }
}

func demo(_ u: Double) {
    // 0–5.5 久坐，5.5–10 活动倒计时，10–14.5 喝水
    let symbolName: String, statusText: String, pulse: Double
    if u < 5.5 {
        symbolName = "figure.seated.side"
        statusText = " \(40 + min(5, Int(u / 0.32)))m"
        pulse = 1 - ease(prog(u, 0, 1.5))
    } else if u < 10 {
        let left = max(0, Int(300 - max(0, u - 5.9) * 72))
        symbolName = "figure.walk"
        statusText = String(format: " %d:%02d", left / 60, left % 60)
        pulse = 1 - ease(prog(u, 5.5, 6.5))
    } else {
        symbolName = "figure.seated.side"
        statusText = " 12m"
        pulse = 0
    }
    desktop(statusSymbol: symbolName, statusText: statusText, pulse: pulse)
    platformPill("macOS", windows: false)

    if u < 5.5 {
        promptWindow(emoji: "🧍", title: "已经坐了 45 分钟啦",
                     message: "站起来伸个懒腰，转转脖子和肩膀\n建议活动 5 分钟",
                     buttons: ["开始活动", "10 分钟后", "跳过"],
                     appear: prog(u, 1.9, 2.4), vanish: prog(u, 5.1, 5.5), pressed: u > 4.7)
    } else if u < 10 {
        let left = max(0, Int(300 - max(0, u - 5.9) * 72))
        promptWindow(emoji: "🚶", title: "活动时间",
                     message: String(format: "剩余 %02d:%02d\n离开座位走一走，结束时会提醒你", left / 60, left % 60),
                     buttons: ["提前结束"], appear: prog(u, 5.5, 6.0), vanish: prog(u, 9.6, 10))
    } else {
        let drank = u > 12.4
        promptWindow(emoji: "💧", title: "该喝水了",
                     message: "小口慢喝一杯温水（约 200ml）\n今日已喝 \(drank ? 4 : 3)/8 杯",
                     buttons: ["喝好了", "10 分钟后"],
                     appear: prog(u, 10.2, 10.7), vanish: prog(u, 13.0, 13.4), pressed: u > 12.0)
        cups(filled: 3, fillingProgress: prog(u, 12.3, 13.0), alpha: ease(prog(u, 10.4, 10.9)))
    }

    let captions = [("⏰ 久坐提醒", "坐满 45 分钟自动弹窗，提醒你起身", 0.0, 5.5),
                    ("🚶 活动倒计时", "离开座位走一走，时间到了再叫你", 5.5, 10.0),
                    ("💧 喝水提醒", "定时提醒喝水，记录每天喝了几杯", 10.0, 14.5)]
    for (title, sub, a, b) in captions {
        withAlpha(sceneAlpha(u, a, b)) {
            label(title, 48, .heavy, at: CGPoint(x: 960, y: 930))
            label(sub, 32, .medium, rgb(0xcbd5e1), at: CGPoint(x: 960, y: 1000))
        }
    }
}

func windowsDemo(_ u: Double) {
    let mins = 40 + min(5, Int(u / 0.3))
    let icon = windowsDesktop(trayText: "\(mins)", trayColor: mins >= 45 ? rgb(0xea580c) : rgb(0x16a34a),
                              pulse: 1 - ease(prog(u, 0, 1.6)))
    promptWindow(emoji: "🧍", title: "已经坐了 45 分钟啦",
                 message: "去接杯水，顺便走两步\n建议活动 5 分钟",
                 buttons: ["开始活动", "10 分钟后", "跳过"],
                 appear: prog(u, 1.9, 2.4), vanish: prog(u, 3.5, 3.9), windows: true)

    let menuRight = icon.maxX + 60, menuBottom = icon.minY - 16
    let settings = windowsMenu(["🪑 已坐 45 分钟 · 10 分钟后提醒起身", "💧 今日喝水 3/8 杯 · 12 分钟后提醒", "-",
                                "现在去活动 5 分钟", "我喝了一杯水", "重置久坐计时", "-",
                                "暂停提醒 ›", "设置 ›", "-", "退出"],
                               right: menuRight, bottom: menuBottom, width: 440, infoRows: 2,
                               hover: u > 4.8 ? "设置 ›" : nil, appear: prog(u, 4.0, 4.3))
    if u > 4.9 {
        windowsMenu(["提醒时段：9:00–18:00 ›", "久坐提醒：45 分钟 ›", "喝水提醒：每 30 分钟 ›",
                     "提示音：Windows Notify ›", "✓  开机自动启动"],
                    right: menuRight - 440 + 4, top: settings.maxY + 8 - (16 + 5 * 40), width: 380,
                    hover: u > 5.4 ? "提醒时段：9:00–18:00 ›" : nil, appear: prog(u, 4.9, 5.2))
    }

    platformPill("Windows 10 / 11", windows: true)
    label("💻 Windows 也能用", 48, .heavy, at: CGPoint(x: 960, y: 930))
    withAlpha(sceneAlpha(u, -1, 4.0)) {
        label("托盘图标直接显示已坐分钟数，到点弹窗提醒", 32, .medium, rgb(0xcbd5e1), at: CGPoint(x: 960, y: 1000))
    }
    withAlpha(sceneAlpha(u, 4.0, 99)) {
        label("同样的菜单和设置，提醒时段、提示音一样不少", 32, .medium, rgb(0xcbd5e1), at: CGPoint(x: 960, y: 1000))
    }
}

func features(_ u: Double) {
    slideIn(prog(u, 0, 0.5)) { d in label("还有这些贴心细节", 64, .heavy, at: CGPoint(x: 960, y: 170 + d)) }
    let items: [(String, String, String, Bool)] = [
        ("🔒", "智能识别离开", "锁屏、合盖或离开 5 分钟，自动算休息", false),
        ("🌙", "提醒时段", "设置 9:00–18:00，下班后不再打扰", true),
        ("⏸️", "一键暂停", "开会时暂停 30 分钟、1 小时或手动恢复", false),
        ("🔔", "自定义提示音", "系统声音，或选择自己的音频文件", false),
    ]
    for (i, item) in items.enumerated() {
        let col = CGFloat(i % 2), row = CGFloat(i / 2)
        let card = CGRect(x: 230 + col * 750, y: 300 + row * 280, width: 710, height: 230)
        slideIn(prog(u, 0.4 + Double(i) * 0.35, 0.9 + Double(i) * 0.35)) { d in
            let r = card.offsetBy(dx: 0, dy: d)
            roundRect(r, 28, fill: NSColor.white.withAlphaComponent(0.1))
            label(item.0, 72, at: CGPoint(x: r.minX + 90, y: r.midY))
            let tw = label(item.1, 42, .bold, at: CGPoint(x: r.minX + 170, y: r.midY - 34), align: .left).width
            if item.3 {
                let badge = CGRect(x: r.minX + 186 + tw, y: r.midY - 52, width: 88, height: 36)
                roundRect(badge, 18, fill: green)
                label("NEW", 20, .heavy, dark, at: CGPoint(x: badge.midX, y: badge.midY))
            }
            label(item.2, 28, .regular, rgb(0xcbd5e1), at: CGPoint(x: r.minX + 170, y: r.midY + 34), align: .left)
        }
    }
}

func outro(_ u: Double) {
    withAlpha(ease(prog(u, 0, 0.5))) {
        scaled(max(easeOutBack(prog(u, 0, 0.7)), 0.01), at: CGPoint(x: 960, y: 290)) {
            appIcon(center: CGPoint(x: 960, y: 290), size: 190)
        }
    }
    slideIn(prog(u, 0.4, 0.9)) { d in label("WorkHealth 1.2.0", 104, .heavy, at: CGPoint(x: 960, y: 500 + d)) }
    slideIn(prog(u, 0.8, 1.3)) { d in
        label("免费 · 开源 · 原生开发 · 无第三方依赖", 42, .medium, rgb(0xcbd5e1), at: CGPoint(x: 960, y: 610 + d))
    }
    slideIn(prog(u, 1.2, 1.7)) { d in
        let url = "github.com/vincentail/work_health"
        let w = attr(url, 38, .semibold, dark).size().width + 90
        let pill = CGRect(x: 960 - w / 2, y: 700 + d, width: w, height: 84)
        roundRect(pill, 42, fill: green)
        label(url, 38, .semibold, dark, at: CGPoint(x: pill.midX, y: pill.midY))
    }
    slideIn(prog(u, 1.6, 2.1)) { d in
        label("macOS 13+（Apple 芯片 / Intel） · Windows 10 / 11", 30, .regular, rgb(0x94a3b8), at: CGPoint(x: 960, y: 860 + d))
    }
}

let scenes: [(Double, Double, (Double) -> Void)] = [
    (0, 4, intro), (4, 8.5, problem), (8.5, 23, demo), (23, 29.5, windowsDemo), (29.5, 35.5, features),
    (35.5, duration, outro),
]

func drawFrame(_ t: Double) {
    background(t)
    for (a, b, draw) in scenes where t >= a && t < b {
        withAlpha(sceneAlpha(t, a, b + (b == duration ? 0.6 : 0))) { draw(t - a) }
    }
}

func render(into c: CGContext, t: Double) {
    ctx = c
    c.saveGState()
    c.translateBy(x: 0, y: H)
    c.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    drawFrame(t)
    NSGraphicsContext.restoreGraphicsState()
    c.restoreGState()
}

// MARK: - 背景音乐（程序合成，无版权问题）

let sampleRate = 44100.0

func freq(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

/// 100 BPM，C–G–Am–F 循环：铺底和弦 + 低音 + 琶音 + 轻鼓点，弹窗出现时加一声铃音
func synthMusic() -> ([Float], [Float]) {
    let n = Int(duration * sampleRate)
    var mixL = [Float](repeating: 0, count: n), mixR = mixL
    var arpL = mixL, arpR = mixL
    let beat = 0.6, bar = beat * 4
    let chords = [[60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60]]

    func add(_ l: inout [Float], _ r: inout [Float], at start: Double, length: Double,
             gain: Double, pan: Double = 0, _ f: (Double) -> Double) {
        let i0 = max(0, Int(start * sampleRate)), i1 = min(n, Int((start + length) * sampleRate))
        guard i0 < i1 else { return }
        let gl = Float(gain * min(1, 1 - pan)), gr = Float(gain * min(1, 1 + pan))
        for i in i0..<i1 {
            let v = Float(f(Double(i) / sampleRate - start))
            l[i] += v * gl
            r[i] += v * gr
        }
    }
    func osc(_ f: Double, _ t: Double) -> Double { sin(2 * .pi * f * t) }

    var noise: UInt32 = 1
    var lastNoise = 0.0
    for b in 0..<Int(ceil(duration / bar)) {
        let t0 = Double(b) * bar
        let chord = chords[b % chords.count]

        // 铺底和弦
        for note in chord {
            let f = freq(note)
            add(&mixL, &mixR, at: t0, length: bar + 0.5, gain: 0.045) { t in
                let env = min(1, t / 0.6) * min(1, max(0, bar + 0.5 - t) / 0.7)
                return (osc(f, t) + 0.6 * osc(f * 1.004, t) + 0.2 * osc(f * 2, t)) * env
            }
        }
        // 低音
        for k in [0, 2] {
            let f = freq(chord[0] - 24)
            add(&mixL, &mixR, at: t0 + Double(k) * beat, length: beat * 1.9, gain: 0.2) { t in
                (osc(f, t) + 0.3 * osc(f * 2, t)) * exp(-t * 2.2) * min(1, t / 0.01)
            }
        }
        // 琶音（从第 4 秒开始）
        if t0 >= 4 - 0.01 {
            let pattern = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 24,
                           chord[2] + 12, chord[1] + 12, chord[0] + 12, chord[1] + 12]
            for (k, note) in pattern.enumerated() {
                let f = freq(note)
                add(&arpL, &arpR, at: t0 + Double(k) * beat / 2, length: 0.9, gain: 0.07,
                    pan: k % 2 == 0 ? -0.35 : 0.35) { t in
                    (osc(f, t) + 0.25 * osc(f * 4, t) * exp(-t * 18)) * exp(-t * 5) * min(1, t / 0.004)
                }
            }
        }
        // 鼓点（演示部分开始）
        if t0 >= 8.5 - 0.01 {
            for k in [0, 2] {
                add(&mixL, &mixR, at: t0 + Double(k) * beat, length: 0.4, gain: 0.32) { t in
                    // 音高从 150Hz 快速滑到 50Hz 的底鼓
                    let phase: Double = 50 * t + 100.0 / 30 * (1 - exp(-t * 30))
                    return sin(2 * .pi * phase) * exp(-t * 9)
                }
            }
            for k in 0..<4 {
                add(&mixL, &mixR, at: t0 + (Double(k) + 0.5) * beat, length: 0.08, gain: 0.05) { t in
                    noise = noise &* 1664525 &+ 1013904223
                    let x = Double(noise >> 8) / Double(1 << 24) * 2 - 1
                    defer { lastNoise = x }
                    return (x - lastNoise) * exp(-t * 45)
                }
            }
        }
    }

    // 提醒弹窗出现时的铃音
    for start in [10.4, 14.0, 18.7, 24.9, 35.5] {
        for (k, note) in [84, 91].enumerated() {
            let f = freq(note)
            add(&mixL, &mixR, at: start + Double(k) * 0.12, length: 2, gain: 0.1) { t in
                (osc(f, t) + 0.4 * osc(f * 2.76, t) * exp(-t * 6)) * exp(-t * 2.5) * min(1, t / 0.003)
            }
        }
    }

    // 琶音加乒乓回声后混入
    let d = Int(0.45 * sampleRate)
    for i in d..<n {
        arpL[i] += 0.35 * arpR[i - d]
        arpR[i] += 0.35 * arpL[i - d]
    }
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let fade = Float(min(1, t / 0.8) * min(1, (duration - t) / 3))
        mixL[i] = tanhf((mixL[i] + arpL[i]) * 1.2) * 0.8 * fade
        mixR[i] = tanhf((mixR[i] + arpR[i]) * 1.2) * 0.8 * fade
    }
    return (mixL, mixR)
}

func writeMusic(to url: URL) throws {
    let (l, r) = synthMusic()
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    var i = 0
    while i < l.count {
        let count = min(Int(sampleRate), l.count - i)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count))!
        buf.frameLength = AVAudioFrameCount(count)
        l.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress! + i, count: count) }
        r.withUnsafeBufferPointer { buf.floatChannelData![1].update(from: $0.baseAddress! + i, count: count) }
        try file.write(from: buf)
        i += count
    }
}

/// 把视频和音乐合成一个 mp4
func mux(video: URL, audio: URL, to out: URL) {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let va = AVURLAsset(url: video), aa = AVURLAsset(url: audio)
            let comp = AVMutableComposition()
            let length = try await va.load(.duration)
            try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
                .insertTimeRange(CMTimeRange(start: .zero, duration: length),
                                 of: try await va.loadTracks(withMediaType: .video)[0], at: .zero)
            let audioLength = min(length, try await aa.load(.duration))
            try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
                .insertTimeRange(CMTimeRange(start: .zero, duration: audioLength),
                                 of: try await aa.loadTracks(withMediaType: .audio)[0], at: .zero)
            let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
            try await export.export(to: out, as: .mp4)
        } catch {
            print("❌ 合成音视频失败: \(error)")
            exit(1)
        }
        done.signal()
    }
    done.wait()
}

// MARK: - 输出

let args = CommandLine.arguments
guard args.count >= 2 else { print("用法: make_promo <输出.mp4> [预览图目录]"); exit(1) }
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

if args.count >= 3 {
    let dir = URL(fileURLWithPath: args[2])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for t in [1.8, 11.5, 16, 21.5, 25.6, 28.8, 33, 39] {
        let c = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                          space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        render(into: c, t: t)
        let png = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
        try! png.write(to: dir.appendingPathComponent(String(format: "frame-%05.1f.png", t)))
    }
    print("✅ 预览图: \(dir.path)")
    exit(0)
}

let url = URL(fileURLWithPath: args[1])
let videoURL = url.deletingPathExtension().appendingPathExtension("video.mp4")
let musicURL = url.deletingPathExtension().appendingPathExtension("music.m4a")
for u in [url, videoURL, musicURL] { try? FileManager.default.removeItem(at: u) }
let writer = try! AVAssetWriter(outputURL: videoURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let total = Int(duration * Double(fps))
for i in 0..<total {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let c = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: Int(W), height: Int(H), bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    autoreleasepool { render(into: c, t: Double(i) / Double(fps)) }
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { print("❌ \(writer.error!)"); exit(1) }

try! writeMusic(to: musicURL)
mux(video: videoURL, audio: musicURL, to: url)
for u in [videoURL, musicURL] { try? FileManager.default.removeItem(at: u) }
print("✅ 视频: \(url.path)")
