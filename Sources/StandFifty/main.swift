import AppKit
import StandFiftyCore

/// 应用装配与系统事件订阅
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var config = AppConfig()
    private var stats: Stats!
    private var away: AwayTracker!
    private var scheduler: Scheduler!
    private var statusBar: StatusBar!

    private let overlay = OverlayController()
    private let settingsWindow = SettingsWindowController()
    /// 抑制 App Nap，保证后台定时器准点触发（不影响系统休眠）
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = AppConfig.load()
        stats = Stats()
        away = AwayTracker(threshold: TimeInterval(config.awayThresholdSeconds))
        scheduler = Scheduler(config: config, stats: stats, away: away)

        // 遮罩关闭后回写状态机
        overlay.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .completed: self.scheduler.complete()
            case .snoozed: self.scheduler.snooze()
            case .skipped: self.scheduler.skip()
            }
        }

        scheduler.onRing = { [weak self] in
            guard let self else { return }
            self.overlay.show(
                restSeconds: TimeInterval(self.scheduler.config.restSeconds),
                anchorMinute: self.scheduler.config.anchorMinute
            )
            self.statusBar?.refresh()
        }

        statusBar = StatusBar(
            scheduler: scheduler,
            onSettings: { [weak self] in self?.openSettings() },
            onTest: { [weak self] in self?.scheduler.ringNow() },
            onQuit: { NSApp.terminate(nil) }
        )
        scheduler.onChange = { [weak self] in self?.statusBar?.refresh() }

        observeSystemEvents()
        scheduler.start()

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "站立提醒需要准点触发"
        )

        // 调试用：`StandFifty --ring-now` 启动即弹遮罩，方便验证 UI
        if CommandLine.arguments.contains("--ring-now") {
            scheduler.ringNow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    // MARK: - 设置

    private func openSettings() {
        settingsWindow.show(config: config) { [weak self] newValue in
            guard let self else { return }
            self.config = newValue.normalized()
            self.config.save()
            self.scheduler.applyConfig(self.config)
            self.statusBar.refresh()
        } onTest: { [weak self] in
            self?.scheduler.ringNow()
        }
    }

    // MARK: - 离开 / 返回判定

    /// 屏保启动、锁屏、显示器睡眠 → 开始记离开时长
    private func beginAway() {
        away.beginAway()
    }

    /// 回到电脑前：闭合离开区间，若遮罩正开着则视为已完成
    private func endAway() {
        guard away.isAway else {
            scheduler.reschedule()
            return
        }
        away.endAway()
        if overlay.isShowing {
            overlay.dismiss()
            scheduler.complete()
        } else {
            scheduler.reschedule()
        }
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.beginAway()
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.endAway()
            }
        }

        // 屏保与锁屏走分布式通知（AppKit 没有对应的高层 API）
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.didstart", "com.apple.screenIsLocked"] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.beginAway()
            }
        }
        for name in ["com.apple.screensaver.didstop", "com.apple.screenIsUnlocked"] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.endAway()
            }
        }
    }
}

// 菜单栏常驻（LSUIElement），无 Dock 图标
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)

// 调试用：`StandFifty --dump-overlay /tmp/overlay.png` 离屏渲染一张遮罩截图
if let index = CommandLine.arguments.firstIndex(of: "--dump-overlay"),
   index + 1 < CommandLine.arguments.count {
    application.finishLaunching()
    let ok = OverlaySnapshot.write(to: CommandLine.arguments[index + 1])
    print(ok ? "已输出遮罩截图" : "输出失败")
    exit(ok ? 0 : 1)
}

// 调试用：`StandFifty --status` 打印当前排期，不启动界面
if CommandLine.arguments.contains("--status") {
    let config = AppConfig.load()
    let away = AwayTracker(threshold: TimeInterval(config.awayThresholdSeconds))
    let scheduler = Scheduler(config: config, stats: Stats(), away: away)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("锚点          : 每小时第 \(config.anchorMinute) 分钟")
    print("工作时段      : \(config.activeStartHour):00 – \(config.activeEndHour):00")
    print("活动门槛      : \(config.awayThresholdSeconds) 秒（本小时累计离开）")
    print("遮罩解锁      : \(config.restSeconds) 秒（连续离开键盘）")
    print("当前时间      : \(formatter.string(from: Date()))")
    print("下次提醒      : \(formatter.string(from: scheduler.nextFire))")
    print("本小时已离开  : \(Int(scheduler.awaySecondsThisHour().rounded())) 秒")
    print("本小时是否免提醒: \(scheduler.isThisHourExempt() ? "是" : "否")")
    exit(0)
}

application.run()
