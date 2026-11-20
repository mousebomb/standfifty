import AppKit
import StandFiftyCore

/// 全屏遮罩：屏保级窗口层级，能盖住全屏 app，但不抢键盘焦点。
/// 遮罩显示期间只累计「净离开键盘」的秒数，摸一下键鼠就停表。
final class OverlayController: NSObject {

    enum Action {
        case completed
        case snoozed
        case skipped
    }

    /// 遮罩关闭时回调（自动完成也算 completed）
    var onAction: ((Action) -> Void)?

    private var windows: [NSWindow] = []
    private var views: [OverlayView] = []
    private var ticker: Timer?
    private var accumulated: TimeInterval = 0
    private var lastTick: Date?
    private var restSeconds: TimeInterval = 60
    private var anchorMinute = 50
    private var finished = true

    var isShowing: Bool { !windows.isEmpty }

    override init() {
        super.init()
        // 插拔显示器时重建遮罩尺寸
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - 显示 / 关闭

    func show(restSeconds: TimeInterval, anchorMinute: Int) {
        dismissWindows()

        self.restSeconds = max(restSeconds, 1)
        self.anchorMinute = anchorMinute
        accumulated = 0
        lastTick = Date()
        finished = false

        for screen in NSScreen.screens {
            buildWindow(on: screen)
        }

        playSound("Glass")
        startTicker()
    }

    func dismiss() {
        finished = true
        ticker?.invalidate()
        ticker = nil
        dismissWindows()
    }

    // MARK: - 私有：窗口

    private func buildWindow(on screen: NSScreen) {
        let window = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 屏保级层级，才能盖住全屏 app；nonactivatingPanel 保证不抢键盘焦点
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false

        let view = OverlayView()
        view.onComplete = { [weak self] in self?.finish(.completed) }
        view.onSnooze = { [weak self] in self?.finish(.snoozed) }
        view.onSkip = { [weak self] in self?.finish(.skipped) }
        view.configure(restSeconds: restSeconds, anchorMinute: anchorMinute)

        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()

        windows.append(window)
        views.append(view)
    }

    private func dismissWindows() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        views.removeAll()
    }

    @objc private func screensChanged() {
        guard isShowing else { return }
        // 尺寸变化：按新屏幕重建窗口，保留已累计的净离开时间
        let snapshot = accumulated
        dismissWindows()
        accumulated = snapshot
        lastTick = Date()
        for screen in NSScreen.screens {
            buildWindow(on: screen)
        }
        views.forEach { $0.update(accumulated: accumulated, restSeconds: restSeconds) }
    }

    // MARK: - 私有：计时

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard !finished, let last = lastTick else { return }
        let now = Date()
        let dt = now.timeIntervalSince(last)
        lastTick = now
        guard dt > 0, dt < 5 else { return } // 休眠唤醒后的巨大间隔不计入

        // 只有在整个 dt 内都没有任何键鼠输入，才算「离开键盘」
        let idle = IdleMonitor.secondsSinceLastInput
        if idle >= dt {
            accumulated += dt
        }

        views.forEach { $0.update(accumulated: accumulated, restSeconds: restSeconds) }

        if accumulated >= restSeconds {
            finish(.completed)
        }
    }

    private func finish(_ action: Action) {
        guard !finished else { return }
        finished = true
        if action == .completed {
            playSound("Hero")
        }
        dismiss()
        onAction?(action)
    }

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}

// MARK: - 遮罩视图

/// 深色全屏内容：标题 + 净离开倒计时 + 进度条 + 三个操作按钮
final class OverlayView: NSView {

    var onComplete: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?

    private let titleLabel = OverlayView.makeLabel(
        text: "该起来活动了",
        font: .systemFont(ofSize: 56, weight: .bold),
        color: .white
    )
    private let subtitleLabel = OverlayView.makeLabel(
        text: "",
        font: .systemFont(ofSize: 20, weight: .regular),
        color: NSColor(white: 1, alpha: 0.72)
    )
    private let hintLabel = OverlayView.makeLabel(
        text: "离开键盘即自动计时 · 凑满后可继续使用电脑",
        font: .systemFont(ofSize: 13, weight: .regular),
        color: NSColor(white: 1, alpha: 0.38)
    )
    private let progressBar = OverlayProgressBar()

    private lazy var completeButton = OverlayView.makeButton(title: "我已起来活动") { [weak self] in self?.onComplete?() }
    private lazy var snoozeButton = OverlayView.makeButton(title: "1 分钟后再提醒") { [weak self] in self?.onSnooze?() }
    private lazy var skipButton = OverlayView.makeButton(title: "本小时已活动过") { [weak self] in self?.onSkip?() }

    private var restSeconds: TimeInterval = 60
    private var anchorMinute = 50

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(progressBar)
        addSubview(hintLabel)
        addSubview(completeButton)
        addSubview(snoozeButton)
        addSubview(skipButton)
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib 初始化") }

    func configure(restSeconds: TimeInterval, anchorMinute: Int) {
        self.restSeconds = restSeconds
        self.anchorMinute = anchorMinute
        hintLabel.stringValue = "离开键盘即自动计时 · 凑满 \(Int(restSeconds)) 秒后可继续使用电脑"
        update(accumulated: 0, restSeconds: restSeconds)
    }

    func update(accumulated: TimeInterval, restSeconds: TimeInterval) {
        self.restSeconds = restSeconds
        let elapsed = Int(accumulated)
        let total = Int(restSeconds)
        subtitleLabel.stringValue = "已离开键盘 \(elapsed) 秒 / \(total) 秒"
        progressBar.progress = min(accumulated / max(restSeconds, 1), 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 近黑底 + 极轻的层次，避免纯黑在广色域屏上显得死板
        NSColor(calibratedWhite: 0.05, alpha: 0.95).setFill()
        bounds.fill()
    }

    override func layout() {
        super.layout()

        let contentWidth = min(bounds.width - 120, 780)
        let x = bounds.midX - contentWidth / 2
        var y = bounds.midY + 96

        titleLabel.frame = NSRect(x: x, y: y, width: contentWidth, height: 66)
        y -= 54
        subtitleLabel.frame = NSRect(x: x, y: y, width: contentWidth, height: 28)
        y -= 40
        progressBar.frame = NSRect(x: x + contentWidth * 0.2, y: y, width: contentWidth * 0.6, height: 8)
        y -= 34
        hintLabel.frame = NSRect(x: x, y: y, width: contentWidth, height: 20)

        // 按钮行居中对齐
        let buttonWidth: CGFloat = 190
        let buttonHeight: CGFloat = 48
        let gap: CGFloat = 16
        let totalWidth = buttonWidth * 3 + gap * 2
        var buttonX = bounds.midX - totalWidth / 2
        let buttonY = bounds.midY - 130
        for button in [completeButton, snoozeButton, skipButton] {
            button.frame = NSRect(x: buttonX, y: buttonY, width: buttonWidth, height: buttonHeight)
            buttonX += buttonWidth + gap
        }
    }

    // MARK: - 工厂

    private static func makeLabel(text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        return label
    }

    private static func makeButton(title: String, action: @escaping () -> Void) -> OverlayPillButton {
        let button = OverlayPillButton(title: title, action: action)
        return button
    }
}

// MARK: - 进度条

final class OverlayProgressBar: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor(white: 1, alpha: 0.14).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        guard progress > 0 else { return }
        let width = max(bounds.height, bounds.width * CGFloat(progress))
        let rect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

// MARK: - 自绘胶囊按钮

final class OverlayPillButton: NSButton {

    private let handler: () -> Void
    private var hovering = false

    init(title: String, action: @escaping () -> Void) {
        self.handler = action
        super.init(frame: .zero)
        self.title = title
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.target = self
        self.action = #selector(clicked)
        self.focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib 初始化") }

    @objc private func clicked() { handler() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        (hovering ? NSColor(white: 1, alpha: 0.82) : NSColor(white: 1, alpha: 0.96)).setFill()
        path.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            in: NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height),
            withAttributes: attributes
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }
}
