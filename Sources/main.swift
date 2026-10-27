import AppKit
import UniformTypeIdentifiers

// MARK: - 偏好设置

enum Prefs {
    private static let d = UserDefaults.standard

    private static func int(_ key: String, _ def: Int) -> Int {
        d.object(forKey: key) == nil ? def : d.integer(forKey: key)
    }

    /// 连续久坐多少分钟后提醒
    static var sitMinutes: Int {
        get { int("sitMinutes", 45) }
        set { d.set(newValue, forKey: "sitMinutes") }
    }
    /// 每次活动多少分钟
    static var breakMinutes: Int {
        get { int("breakMinutes", 5) }
        set { d.set(newValue, forKey: "breakMinutes") }
    }
    /// 喝水提醒间隔（分钟），0 表示关闭
    static var waterMinutes: Int {
        get { int("waterMinutes", 30) }
        set { d.set(newValue, forKey: "waterMinutes") }
    }
    /// 离开电脑（无键鼠操作）多少分钟视为已经休息过
    static var idleResetMinutes: Int {
        get { int("idleResetMinutes", 5) }
        set { d.set(newValue, forKey: "idleResetMinutes") }
    }
    /// 稍后提醒的分钟数
    static var snoozeMinutes: Int {
        get { int("snoozeMinutes", 10) }
        set { d.set(newValue, forKey: "snoozeMinutes") }
    }
    /// 每天几点开始提醒（从 0 点起的分钟数），-1 表示不限
    static var startMinute: Int {
        get { int("startMinute", -1) }
        set { d.set(newValue, forKey: "startMinute") }
    }
    /// 每天几点结束提醒（从 0 点起的分钟数），-1 表示不限
    static var endMinute: Int {
        get { int("endMinute", -1) }
        set { d.set(newValue, forKey: "endMinute") }
    }
    static func clock(_ minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
    }
    static var waterGoal: Int {
        get { int("waterGoal", 8) }
        set { d.set(newValue, forKey: "waterGoal") }
    }
    static var soundOn: Bool {
        get { d.object(forKey: "soundOn") == nil ? true : d.bool(forKey: "soundOn") }
        set { d.set(newValue, forKey: "soundOn") }
    }
    /// 提示音：系统声音名（如 Glass），或自定义音频文件的绝对路径
    static var soundName: String {
        get { d.string(forKey: "soundName") ?? "Glass" }
        set { d.set(newValue, forKey: "soundName") }
    }

    /// 提醒弹窗里的宠物
    static var pet: Pet {
        get { Pet(rawValue: d.string(forKey: "pet") ?? "") ?? .cat }
        set { d.set(newValue.rawValue, forKey: "pet") }
    }

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "water-" + f.string(from: Date())
    }
    static var waterToday: Int {
        get { d.integer(forKey: todayKey) }
        set { d.set(newValue, forKey: todayKey) }
    }
}

// MARK: - 提示音

enum Sounds {
    /// 系统自带及 ~/Library/Sounds 下的声音名
    static var available: [String] {
        let dirs = ["/System/Library/Sounds",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds").path]
        let names = dirs.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
            .map { ($0 as NSString).deletingPathExtension }
        return Array(Set(names)).sorted()
    }

    static func isCustom(_ name: String) -> Bool { name.hasPrefix("/") }

    static func label(_ name: String) -> String {
        isCustom(name) ? (name as NSString).lastPathComponent : name
    }

    private static var current: NSSound?

    static func play(_ name: String = Prefs.soundName) {
        current?.stop()
        current = isCustom(name)
            ? NSSound(contentsOf: URL(fileURLWithPath: name), byReference: true)
            : NSSound(named: name)
        (current ?? NSSound(named: "Glass"))?.play()
    }
}

// MARK: - 开机启动（LaunchAgent）

enum LoginItem {
    static let label = "com.workhealth.healthreminder"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ on: Bool) {
        if on {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: plistURL, atomically: true)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}

// MARK: - UI 小组件

final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, checked: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

final class ClosureButton: NSButton {
    private var handler: (() -> Void)?
    convenience init(_ title: String, primary: Bool = false, _ handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(fire)
        bezelStyle = .rounded
        controlSize = .large
        if primary { keyEquivalent = "\r" }
    }
    @objc private func fire() { handler?() }
}

// MARK: - 宠物动画

enum Pet: String, CaseIterable {
    case cat, dog, off = "none"
    var label: String {
        switch self {
        case .cat: return "猫 🐱"
        case .dog: return "狗 🐶"
        case .off: return "关闭"
        }
    }
}

/// calm：呼吸、招手；active：蹦跳（活动中）；happy：眯眼开心（活动完成）
enum PetMood { case calm, active, happy }

/// 弹窗里的小猫/小狗，纯代码绘制，带呼吸、眨眼、摇尾巴、招手动画；旁边的气泡里显示提醒 emoji
final class PetView: NSView {
    static let size = NSSize(width: 170, height: 112)
    private let pet: Pet
    private let mood: PetMood
    private let emoji: String
    private let start = Date()
    private var timer: Timer?

    init(pet: Pet, mood: PetMood, emoji: String) {
        self.pet = pet
        self.mood = mood
        self.emoji = emoji
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }

    private func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }
    private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private func oval(_ g: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGColor) {
        g.setFillColor(c)
        g.fillEllipse(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }
    private func poly(_ g: CGContext, _ c: CGColor, _ points: CGPoint...) {
        g.setFillColor(c)
        g.beginPath()
        g.addLines(between: points)
        g.closePath()
        g.fillPath()
    }
    private func stroke(_ g: CGContext, _ width: CGFloat, _ c: CGColor, _ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        g.addPath(path)
        g.setStrokeColor(c)
        g.setLineWidth(width)
        g.setLineCap(.round)
        g.strokePath()
    }
    private func rotated(_ g: CGContext, _ angle: CGFloat, around p: CGPoint, _ body: () -> Void) {
        g.saveGState()
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: angle)
        g.translateBy(x: -p.x, y: -p.y)
        body()
        g.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        let t = Date().timeIntervalSince(start)
        let cat = pet == .cat
        let fur = color(cat ? 0xF6A04D : 0xE3B577), cream = color(0xFFF3E0)
        let ink = color(0x3B2A20), pink = color(0xF28CA0), white = color(0xFFFFFF)

        let hop: CGFloat
        switch mood {
        case .calm: hop = 1.5 + 1.5 * CGFloat(sin(t * 2.4))
        case .active: hop = 9 * CGFloat(abs(sin(t * 5)))
        case .happy: hop = 5 * CGFloat(abs(sin(t * 4)))
        }
        oval(g, 85, 106, 62 - hop * 2, 8, color(0x000000, 0.12))

        g.saveGState()
        g.translateBy(x: 25, y: -hop)

        // 尾巴
        let wag = CGFloat(sin(t * (cat ? 3 : mood == .calm ? 8 : 14))) * (cat ? 0.35 : 0.5)
        rotated(g, wag, around: P(80, 88)) {
            stroke(g, cat ? 9 : 8, fur) { p in
                p.move(to: P(80, 88))
                if cat { p.addQuadCurve(to: P(104, 50), control: P(112, 90)) }
                else { p.addQuadCurve(to: P(102, 68), control: P(100, 88)) }
            }
        }

        // 身体和脚
        oval(g, 60, 82, 58, 40, fur)
        oval(g, 60, 86, 30, 24, cream)
        let waving = mood == .calm && t.truncatingRemainder(dividingBy: 4) < 1.6
        oval(g, 46, 100, 16, 10, fur)
        if !waving { oval(g, 74, 100, 16, 10, fur) }

        // 猫耳朵（右耳偶尔抖一下）
        if cat {
            poly(g, fur, P(32, 36), P(36, 6), P(56, 24))
            poly(g, pink, P(38, 30), P(39, 13), P(51, 24))
            let twitch: CGFloat = t.truncatingRemainder(dividingBy: 5) < 0.2 ? 0.18 : 0
            rotated(g, twitch, around: P(76, 30)) {
                poly(g, fur, P(88, 36), P(84, 6), P(64, 24))
                poly(g, pink, P(82, 30), P(81, 13), P(69, 24))
            }
        }

        // 头
        oval(g, 60, 48, 66, 56, fur)
        if cat {
            stroke(g, 3, color(0xD97F2E)) { p in
                for x: CGFloat in [54, 60, 66] {
                    p.move(to: P(x, x == 60 ? 22 : 24))
                    p.addLine(to: P(x, 31))
                }
            }
        } else {
            // 狗：耷拉的耳朵会轻轻晃，嘴巴一圈浅色
            let flap = CGFloat(sin(t * 3)) * 0.08
            rotated(g, 0.35 + flap, around: P(30, 30)) { oval(g, 30, 46, 20, 38, color(0x9C6B3E)) }
            rotated(g, -0.35 - flap, around: P(90, 30)) { oval(g, 90, 46, 20, 38, color(0x9C6B3E)) }
            oval(g, 60, 60, 30, 20, cream)
        }

        // 眼睛：开心时眯成 ^ ^，平时每隔几秒眨一次
        for x: CGFloat in [47, 73] {
            let y: CGFloat = 48
            if mood == .happy {
                stroke(g, 2.5, ink) { p in
                    p.move(to: P(x - 5, y + 2))
                    p.addQuadCurve(to: P(x + 5, y + 2), control: P(x, y - 6))
                }
            } else if t.truncatingRemainder(dividingBy: 3.4) > 3.25 {
                stroke(g, 2.5, ink) { p in
                    p.move(to: P(x - 4, y))
                    p.addLine(to: P(x + 4, y))
                }
            } else {
                oval(g, x, y, 8, 10, ink)
                oval(g, x + 1.5, y - 2.5, 3, 3, white)
            }
        }

        // 腮红、鼻子、嘴
        oval(g, 38, 60, 10, 6, color(0xF28CA0, 0.45))
        oval(g, 82, 60, 10, 6, color(0xF28CA0, 0.45))
        if cat { poly(g, pink, P(56, 55), P(64, 55), P(60, 59.5)) }
        else { oval(g, 60, 56, 12, 8, ink) }
        if !cat && mood != .calm { oval(g, 60, 67, 9, 11, color(0xF06A80)) }
        stroke(g, 1.6, ink) { p in
            p.move(to: P(60, 59))
            p.addLine(to: P(60, 62))
            p.move(to: P(54, 61))
            p.addQuadCurve(to: P(60, 62), control: P(57, 66))
            p.addQuadCurve(to: P(66, 61), control: P(63, 66))
        }
        if cat {
            stroke(g, 1.2, color(0x3B2A20, 0.5)) { p in
                for (a, b) in [(P(36, 58), P(22, 55)), (P(36, 62), P(22, 64)),
                               (P(84, 58), P(98, 55)), (P(84, 62), P(98, 64))] {
                    p.move(to: a)
                    p.addLine(to: b)
                }
            }
        }

        // 招手
        if waving {
            let y = 64 + CGFloat(sin(t * 12)) * 4
            oval(g, 95, y, 15, 15, fur)
            oval(g, 95, y + 2, 7, 5, color(0xF28CA0, 0.8))
        }
        g.restoreGState()

        // 气泡
        let by = 4 + CGFloat(sin(t * 2)) * 2
        let bubble = CGRect(x: 120, y: by, width: 46, height: 40)
        g.setStrokeColor(color(0xCBD5E1))
        g.setLineWidth(1)
        for r in [bubble, CGRect(x: 124, y: by + 43, width: 7, height: 7)] {
            g.addPath(CGPath(roundedRect: r, cornerWidth: min(14, r.width / 2), cornerHeight: min(14, r.height / 2),
                             transform: nil))
            g.setFillColor(white)
            g.drawPath(using: .fillStroke)
        }
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let sz = text.size()
        text.draw(at: P(bubble.midX - sz.width / 2, bubble.midY - sz.height / 2))
    }
}

/// 置顶、所有桌面可见的提醒弹窗
final class PromptWindow: NSPanel {
    let messageLabel = NSTextField(wrappingLabelWithString: "")

    init(emoji: String, title: String, message: String, buttons: [NSButton], mood: PetMood = .calm) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                   styleMask: [.titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSVisualEffectView()
        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        contentView = bg

        let top: NSView
        if Prefs.pet == .off {
            let emojiLabel = NSTextField(labelWithString: emoji)
            emojiLabel.font = .systemFont(ofSize: 52)
            top = emojiLabel
        } else {
            top = PetView(pet: Prefs.pet, mood: mood, emoji: emoji)
        }
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 20)
        messageLabel.stringValue = message
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.preferredMaxLayoutWidth = 360

        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 10

        let stack = NSStackView(views: [top, titleLabel, messageLabel, row])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(20, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 36),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -30),
            bg.widthAnchor.constraint(equalToConstant: 420),
        ])
        bg.layoutSubtreeIfNeeded()
        setContentSize(bg.fittingSize)
        center()
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - 主逻辑

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    private var sitStart = Date()          // 本轮久坐开始时间
    private var lastWater = Date()         // 上次喝水时间
    private var sitSnoozeUntil: Date?
    private var waterSnoozeUntil: Date?
    private var pausedUntil: Date?         // 暂停提醒（distantFuture = 手动恢复）
    private var breakEnd: Date?            // 正在活动时的结束时间
    private var appNapActivity: NSObjectProtocol?

    private enum PromptKind { case sit, water, onBreak, done }
    private var prompt: PromptWindow?
    private var promptKind: PromptKind?

    private let sitTips = [
        "站起来伸个懒腰，转转脖子和肩膀",
        "去接杯水，顺便走两步",
        "做 10 个深蹲，或者靠墙站一会儿",
        "望望窗外远处，让眼睛也休息一下",
        "活动一下手腕和腰，别让颈椎太累",
    ]
    private let waterTips = [
        "小口慢喝一杯温水（约 200ml）",
        "口渴时其实已经缺水了，现在就喝一点",
        "喝口水，顺便让眼睛离开屏幕 20 秒",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusButton()

        // 菜单栏应用没有可见窗口，会被 App Nap 降频导致计时器长时间不触发
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "久坐/喝水计时")

        // 用系统休眠/唤醒通知判断休眠，而不是靠计时器间隔猜测
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, breakEnd == nil else { return }
            resetSit()
            if promptKind == .sit { closePrompt() }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.3
    }

    // MARK: 计时

    /// 距离上次键盘/鼠标操作的秒数
    private var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    private func tick() {
        let now = Date()
        let idle = idleSeconds
        let away = idle >= Double(Prefs.idleResetMinutes * 60)

        // 用户离开足够久：视为已经休息
        if away && breakEnd == nil {
            resetSit()
            if promptKind == .sit { closePrompt() }
        }

        if let until = pausedUntil {
            if now >= until { pausedUntil = nil; resetSit(); lastWater = now }
            else { updateStatusButton(); return }
        }

        // 不在每天的提醒时段内：不提醒，计时从开始时间算起
        if breakEnd == nil && offHours {
            resetSit()
            lastWater = now
            waterSnoozeUntil = nil
            updateStatusButton()
            return
        }

        if let end = breakEnd {
            let left = end.timeIntervalSince(now)
            if left <= 0 { finishBreak() }
            else { prompt?.messageLabel.stringValue = breakMessage(left) }
            updateStatusButton()
            return
        }

        if prompt == nil {
            if now >= sitDue {
                showSitPrompt()
            } else if Prefs.waterMinutes > 0, now >= waterDue, idle < 120 {
                // 用户在电脑前才提醒喝水，否则等回来再弹
                showWaterPrompt()
            }
        }
        updateStatusButton()
    }

    /// 当前时刻（从 0 点起的分钟数）
    private var minuteOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return c.hour! * 60 + c.minute!
    }

    /// 当前是否不在每天的提醒时段内
    private var offHours: Bool {
        let m = minuteOfDay
        return (Prefs.startMinute >= 0 && m < Prefs.startMinute)
            || (Prefs.endMinute >= 0 && m >= Prefs.endMinute)
    }

    private var sitDue: Date {
        let due = sitStart.addingTimeInterval(Double(Prefs.sitMinutes * 60))
        return max(due, sitSnoozeUntil ?? .distantPast)
    }

    private var waterDue: Date {
        let due = lastWater.addingTimeInterval(Double(Prefs.waterMinutes * 60))
        return max(due, waterSnoozeUntil ?? .distantPast)
    }

    private func resetSit() {
        sitStart = Date()
        sitSnoozeUntil = nil
    }

    // MARK: 提醒动作

    private func showSitPrompt() {
        let mins = Int(Date().timeIntervalSince(sitStart) / 60)
        show(.sit, emoji: "🧍", title: "已经坐了 \(mins) 分钟啦",
             message: "\(sitTips.randomElement()!)\n建议活动 \(Prefs.breakMinutes) 分钟",
             buttons: [
                ClosureButton("开始活动", primary: true) { [weak self] in self?.startBreak() },
                ClosureButton("\(Prefs.snoozeMinutes) 分钟后") { [weak self] in
                    guard let self else { return }
                    sitSnoozeUntil = Date().addingTimeInterval(Double(Prefs.snoozeMinutes * 60))
                    closePrompt()
                },
                ClosureButton("跳过") { [weak self] in self?.resetSit(); self?.closePrompt() },
             ])
    }

    private func showWaterPrompt() {
        show(.water, emoji: "💧", title: "该喝水了",
             message: "\(waterTips.randomElement()!)\n今日已喝 \(Prefs.waterToday)/\(Prefs.waterGoal) 杯",
             buttons: [
                ClosureButton("喝好了", primary: true) { [weak self] in self?.drinkWater(); self?.closePrompt() },
                ClosureButton("\(Prefs.snoozeMinutes) 分钟后") { [weak self] in
                    guard let self else { return }
                    waterSnoozeUntil = Date().addingTimeInterval(Double(Prefs.snoozeMinutes * 60))
                    closePrompt()
                },
             ])
    }

    private func startBreak() {
        closePrompt()
        pausedUntil = nil
        let end = Date().addingTimeInterval(Double(Prefs.breakMinutes * 60))
        breakEnd = end
        show(.onBreak, emoji: "🚶", title: "活动时间",
             message: breakMessage(end.timeIntervalSinceNow),
             buttons: [ClosureButton("提前结束") { [weak self] in self?.finishBreak() }],
             sound: false)
    }

    private func breakMessage(_ left: TimeInterval) -> String {
        let s = max(0, Int(left.rounded(.up)))
        return String(format: "剩余 %02d:%02d\n离开座位走一走，结束时会提醒你", s / 60, s % 60)
    }

    private func finishBreak() {
        breakEnd = nil
        resetSit()
        closePrompt()
        show(.done, emoji: "✅", title: "活动完成，继续加油！",
             message: "顺便喝口水吧，今日已喝 \(Prefs.waterToday)/\(Prefs.waterGoal) 杯",
             buttons: [
                ClosureButton("喝了一杯", primary: true) { [weak self] in self?.drinkWater(); self?.closePrompt() },
                ClosureButton("好的") { [weak self] in self?.closePrompt() },
             ])
    }

    private func drinkWater() {
        Prefs.waterToday += 1
        lastWater = Date()
        waterSnoozeUntil = nil
        updateStatusButton()
    }

    private func show(_ kind: PromptKind, emoji: String, title: String, message: String,
                      buttons: [NSButton], sound: Bool = true) {
        closePrompt()
        let mood: PetMood = kind == .onBreak ? .active : kind == .done ? .happy : .calm
        let w = PromptWindow(emoji: emoji, title: title, message: message, buttons: buttons, mood: mood)
        prompt = w
        promptKind = kind
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        if sound && Prefs.soundOn { Sounds.play() }
    }

    private func closePrompt() {
        prompt?.close()
        prompt = nil
        promptKind = nil
    }

    // MARK: 菜单栏

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let symbol: String
        let text: String
        if let end = breakEnd {
            let s = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
            symbol = "figure.walk"
            text = String(format: " %d:%02d", s / 60, s % 60)
        } else if pausedUntil != nil {
            symbol = "pause.circle"
            text = ""
        } else if offHours {
            symbol = "moon.zzz"
            text = ""
        } else {
            symbol = "figure.seated.side"
            text = " \(Int(Date().timeIntervalSince(sitStart) / 60))m"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = text
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()

        func info(_ s: String) -> NSMenuItem {
            let item = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        func mins(_ t: TimeInterval) -> Int { max(0, Int((t / 60).rounded(.up))) }

        if let end = breakEnd {
            menu.addItem(info("🚶 活动中，还剩 \(mins(end.timeIntervalSince(now))) 分钟"))
        } else if let until = pausedUntil {
            menu.addItem(info(until == .distantFuture ? "⏸ 已暂停提醒"
                              : "⏸ 已暂停，\(mins(until.timeIntervalSince(now))) 分钟后恢复"))
        } else if offHours {
            let ended = Prefs.endMinute >= 0 && minuteOfDay >= Prefs.endMinute
            var s = ended ? "🌙 已过 \(Prefs.clock(Prefs.endMinute))，今天的提醒已结束" : "🌙 还没到开始时间"
            if Prefs.startMinute >= 0 { s += " · 每天 \(Prefs.clock(Prefs.startMinute)) 开始" }
            menu.addItem(info(s))
        } else {
            let sat = Int(now.timeIntervalSince(sitStart) / 60)
            menu.addItem(info("🪑 已坐 \(sat) 分钟 · \(mins(sitDue.timeIntervalSince(now))) 分钟后提醒起身"))
        }
        var water = "💧 今日喝水 \(Prefs.waterToday)/\(Prefs.waterGoal) 杯"
        if Prefs.waterMinutes > 0 && breakEnd == nil && pausedUntil == nil && !offHours {
            water += " · \(mins(waterDue.timeIntervalSince(now))) 分钟后提醒"
        }
        menu.addItem(info(water))
        menu.addItem(.separator())

        if breakEnd == nil {
            menu.addItem(ActionItem("现在去活动 \(Prefs.breakMinutes) 分钟") { [weak self] in self?.startBreak() })
        } else {
            menu.addItem(ActionItem("结束活动") { [weak self] in self?.finishBreak() })
        }
        menu.addItem(ActionItem("我喝了一杯水") { [weak self] in self?.drinkWater() })
        menu.addItem(ActionItem("重置久坐计时") { [weak self] in self?.resetSit() })
        menu.addItem(.separator())

        if pausedUntil != nil {
            menu.addItem(ActionItem("恢复提醒") { [weak self] in
                self?.pausedUntil = nil; self?.resetSit(); self?.lastWater = Date()
            })
        } else {
            let pause = NSMenu()
            for (title, minutes) in [("30 分钟", 30), ("1 小时", 60), ("2 小时", 120), ("直到手动恢复", 0)] {
                pause.addItem(ActionItem(title) { [weak self] in
                    guard let self else { return }
                    if breakEnd != nil { breakEnd = nil }
                    closePrompt()
                    pausedUntil = minutes == 0 ? .distantFuture
                        : Date().addingTimeInterval(Double(minutes * 60))
                    updateStatusButton()
                })
            }
            menu.addItem(submenu("暂停提醒", pause))
        }

        let settings = NSMenu()
        settings.addItem(hoursMenu())
        settings.addItem(choice("久坐提醒", [25, 30, 45, 60, 90], Prefs.sitMinutes, { "\($0) 分钟" }) {
            Prefs.sitMinutes = $0
        })
        settings.addItem(choice("每次活动", [2, 3, 5, 10, 15], Prefs.breakMinutes, { "\($0) 分钟" }) {
            Prefs.breakMinutes = $0
        })
        settings.addItem(choice("喝水提醒", [0, 20, 30, 45, 60, 90], Prefs.waterMinutes,
                                { $0 == 0 ? "关闭" : "每 \($0) 分钟" }) { [weak self] in
            Prefs.waterMinutes = $0
            self?.lastWater = Date()
        })
        settings.addItem(choice("喝水目标", [6, 8, 10, 12], Prefs.waterGoal, { "\($0) 杯/天" }) {
            Prefs.waterGoal = $0
        })
        settings.addItem(choice("稍后提醒", [5, 10, 15], Prefs.snoozeMinutes, { "\($0) 分钟" }) {
            Prefs.snoozeMinutes = $0
        })
        settings.addItem(choice("离开多久算休息", [3, 5, 10], Prefs.idleResetMinutes, { "\($0) 分钟" }) {
            Prefs.idleResetMinutes = $0
        })
        settings.addItem(.separator())
        settings.addItem(soundMenu())
        let pets = NSMenu()
        for pet in Pet.allCases {
            pets.addItem(ActionItem(pet.label, checked: pet == Prefs.pet) { Prefs.pet = pet })
        }
        settings.addItem(submenu("弹窗宠物：\(Prefs.pet.label)", pets))
        settings.addItem(ActionItem("开机自动启动", checked: LoginItem.isEnabled) {
            LoginItem.setEnabled(!LoginItem.isEnabled)
        })
        menu.addItem(submenu("设置", settings))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func hoursMenu() -> NSMenuItem {
        let sub = NSMenu()
        let clock = { (m: Int) in m < 0 ? "不限" : Prefs.clock(m) }
        sub.addItem(choice("开始", [-1, 420, 450, 480, 510, 540, 570, 600, 630], Prefs.startMinute, clock) {
            Prefs.startMinute = $0
        })
        sub.addItem(choice("结束", [-1, 1020, 1050, 1080, 1110, 1140, 1170, 1200, 1260, 1320], Prefs.endMinute, clock) {
            Prefs.endMinute = $0
        })
        let (start, end) = (Prefs.startMinute, Prefs.endMinute)
        let range = start < 0 && end < 0 ? "全天"
            : "\(start < 0 ? "0:00" : Prefs.clock(start))–\(end < 0 ? "24:00" : Prefs.clock(end))"
        return submenu("提醒时段：\(range)", sub)
    }

    private func soundMenu() -> NSMenuItem {
        let sub = NSMenu()
        let current = Prefs.soundName
        sub.addItem(ActionItem("关闭", checked: !Prefs.soundOn) { Prefs.soundOn = false })
        sub.addItem(.separator())
        for name in Sounds.available {
            sub.addItem(ActionItem(name, checked: Prefs.soundOn && name == current) {
                Prefs.soundOn = true
                Prefs.soundName = name
                Sounds.play(name)
            })
        }
        sub.addItem(.separator())
        if Sounds.isCustom(current) {
            sub.addItem(ActionItem("自定义：\(Sounds.label(current))", checked: Prefs.soundOn) {
                Prefs.soundOn = true
                Sounds.play(current)
            })
        }
        sub.addItem(ActionItem("选择音频文件…") { [weak self] in self?.pickSoundFile() })
        return submenu("提示音：\(Prefs.soundOn ? Sounds.label(current) : "关闭")", sub)
    }

    private func pickSoundFile() {
        let panel = NSOpenPanel()
        panel.title = "选择提示音"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Prefs.soundOn = true
        Prefs.soundName = url.path
        Sounds.play(url.path)
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    private func choice(_ title: String, _ options: [Int], _ current: Int,
                        _ label: @escaping (Int) -> String, _ set: @escaping (Int) -> Void) -> NSMenuItem {
        let sub = NSMenu()
        for v in options {
            sub.addItem(ActionItem(label(v), checked: v == current) { set(v) })
        }
        let item = submenu("\(title)：\(label(current))", sub)
        return item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
