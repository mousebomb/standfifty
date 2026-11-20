import AppKit
import ServiceManagement
import StandFiftyCore

/// 菜单栏：常驻倒计时 + 下拉菜单（下次提醒、本小时离开时长、今日计数、设置、自启、退出）
final class StatusBar: NSObject {

    private let item: NSStatusItem
    private let scheduler: Scheduler
    private let onSettings: () -> Void
    private let onTest: () -> Void
    private let onQuit: () -> Void

    private let nextItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let awayItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let todayItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "开机自启", action: nil, keyEquivalent: "")

    private var refreshTimer: Timer?

    init(
        scheduler: Scheduler,
        onSettings: @escaping () -> Void,
        onTest: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.scheduler = scheduler
        self.onSettings = onSettings
        self.onTest = onTest
        self.onQuit = onQuit
        super.init()

        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        buildMenu()
        refresh()

        // 1 秒刷新一次倒计时足够，菜单没打开时也几乎无开销
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    // MARK: - 菜单

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for staticItem in [nextItem, awayItem, todayItem] {
            staticItem.isEnabled = false
            menu.addItem(staticItem)
        }

        menu.addItem(.separator())

        let testItem = NSMenuItem(title: "立即测试提醒", action: #selector(testTapped), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settingsTapped), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchItem.target = self
        launchItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 StandFifty", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    // MARK: - 刷新

    func refresh() {
        let now = Date()
        updateTitle(now: now)
        nextItem.title = nextLine(now: now)
        awayItem.title = awayLine(now: now)
        todayItem.title = "今日：提醒 \(scheduler.stats.reminders) · 完成 \(scheduler.stats.completed)"
        launchItem.state = Self.launchAtLoginEnabled ? .on : .off
    }

    private func updateTitle(now: Date) {
        guard let button = item.button else { return }
        if scheduler.phase == .ringing {
            button.title = "起来！"
            return
        }
        if scheduler.isSnoozing {
            let seconds = Int(scheduler.remainingSeconds.rounded())
            button.title = "延后 \(seconds)s"
            return
        }
        // 显示还有几分钟，向下取整会让 59 秒剩余显示 0 分钟，改用向上取整
        let minutes = Int(ceil(scheduler.remainingSeconds / 60))
        button.title = "\(minutes)m"
    }

    private func nextLine(now: Date) -> String {
        if scheduler.isSnoozing {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "延后中，\(formatter.string(from: scheduler.nextFire)) 再提醒"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let target = formatter.string(from: scheduler.nextFire)
        let remaining = Int(scheduler.remainingSeconds.rounded())
        if remaining >= 60 {
            return "下次提醒 \(target)（还有 \(remaining / 60) 分 \(remaining % 60) 秒）"
        }
        return "下次提醒 \(target)（还有 \(remaining) 秒）"
    }

    private func awayLine(now: Date) -> String {
        let seconds = Int(scheduler.awaySecondsThisHour(now: now).rounded())
        let threshold = scheduler.config.awayThresholdSeconds
        let text = "本小时已离开 \(seconds / 60) 分 \(seconds % 60) 秒"
        if seconds >= threshold {
            return "\(text) · 已达 \(threshold) 秒门槛，本小时免提醒"
        }
        return "\(text)（满 \(threshold) 秒则本小时免提醒）"
    }

    // MARK: - 动作

    @objc private func testTapped() { onTest() }

    @objc private func settingsTapped() { onSettings() }

    @objc private func quitTapped() { onQuit() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // 失败通常是 app 不在 /Applications 或签名不合规，直接提示原因
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = "\(error.localizedDescription)\n\n请确认 StandFifty.app 已安装到 /Applications 目录。"
            alert.alertStyle = .warning
            alert.runModal()
        }
        refresh()
    }

    private static var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
