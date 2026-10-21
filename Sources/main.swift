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

/// 置顶、所有桌面可见的提醒弹窗
final class PromptWindow: NSPanel {
    let messageLabel = NSTextField(wrappingLabelWithString: "")

    init(emoji: String, title: String, message: String, buttons: [NSButton]) {
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

        let emojiLabel = NSTextField(labelWithString: emoji)
        emojiLabel.font = .systemFont(ofSize: 52)
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

        let stack = NSStackView(views: [emojiLabel, titleLabel, messageLabel, row])
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
        let w = PromptWindow(emoji: emoji, title: title, message: message, buttons: buttons)
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
        } else {
            let sat = Int(now.timeIntervalSince(sitStart) / 60)
            menu.addItem(info("🪑 已坐 \(sat) 分钟 · \(mins(sitDue.timeIntervalSince(now))) 分钟后提醒起身"))
        }
        var water = "💧 今日喝水 \(Prefs.waterToday)/\(Prefs.waterGoal) 杯"
        if Prefs.waterMinutes > 0 && breakEnd == nil && pausedUntil == nil {
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
        settings.addItem(ActionItem("开机自动启动", checked: LoginItem.isEnabled) {
            LoginItem.setEnabled(!LoginItem.isEnabled)
        })
        menu.addItem(submenu("设置", settings))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
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
