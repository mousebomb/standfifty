import Foundation
import StandFiftyCore

/// 提醒节奏状态机：只有「等待」和「正在提醒」两态。
/// 核心约束：无论用户怎么点（延后 / 活动过），下一次提醒永远落在下一小时的锚点上，绝不漂移。
final class Scheduler {

    enum Phase {
        case waiting
        case ringing
    }

    private(set) var config: AppConfig
    private(set) var phase: Phase = .waiting
    /// 下一次提醒时刻（延后期间等于延后到期时刻）
    private(set) var nextFire: Date
    /// 已经处理过的自然小时（决定是否还要补提醒）
    private(set) var lastHandledHour: Date? {
        didSet { persistLastHandledHour() }
    }
    private(set) var snoozeUntil: Date?

    let away: AwayTracker
    let stats: Stats

    private let calendar: Calendar
    private var timer: Timer?
    /// 手动触发（菜单里的「立即测试」）不计数、不占用本小时
    private var isManualRing = false

    /// 需要弹遮罩
    var onRing: (() -> Void)?
    /// 状态变化，菜单栏刷新用
    var onChange: (() -> Void)?

    init(config: AppConfig, stats: Stats, away: AwayTracker, calendar: Calendar = .current) {
        self.config = config.normalized()
        self.stats = stats
        self.away = away
        self.calendar = calendar
        self.away.threshold = TimeInterval(self.config.awayThresholdSeconds)
        self.nextFire = Schedule.nextFire(after: Date(), config: self.config, calendar: calendar)
        self.lastHandledHour = Scheduler.loadLastHandledHour()
    }

    // MARK: - 生命周期

    func start() {
        timer?.invalidate()
        // 0.5 秒足够准（锚点粒度是分钟），又不会白耗电
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 用户操作

    /// 菜单里的「立即测试提醒」：不计数、不占用本小时
    func ringNow() {
        guard phase == .waiting else { return }
        isManualRing = true
        phase = .ringing
        onRing?()
        onChange?()
    }

    /// 用户确认「本小时我活动过」（自动凑满 60 秒也走这里）
    func complete() {
        guard phase == .ringing else { return }
        finishRing()
    }

    /// 用户点「延后 1 分钟」
    func snooze() {
        guard phase == .ringing else { return }
        isManualRing = false
        phase = .waiting
        let until = Date().addingTimeInterval(TimeInterval(config.snoozeSeconds))
        snoozeUntil = until
        nextFire = until
        onChange?()
    }

    /// 配置变更后重算
    func applyConfig(_ newConfig: AppConfig) {
        config = newConfig.normalized()
        away.threshold = TimeInterval(config.awayThresholdSeconds)
        guard phase == .waiting else { onChange?(); return }
        if snoozeUntil == nil {
            nextFire = Schedule.nextFire(after: Date(), config: config, calendar: calendar)
        }
        onChange?()
    }

    // MARK: - 唤醒 / 解锁后重算

    func reschedule() {
        let now = Date()
        away.prune(before: calendar.date(byAdding: .hour, value: -1, to: now) ?? now)
        stats.rolloverIfNeeded(now: now)

        guard phase == .waiting else { onChange?(); return }
        if let until = snoozeUntil, now >= until, !away.isAway {
            snoozeUntil = nil
            fire(now: now)
            return
        }
        nextFire = catchUpOrNext(now)
        onChange?()
    }

    // MARK: - 展示用文案

    /// 距离下次提醒的剩余秒数
    var remainingSeconds: TimeInterval {
        max(nextFire.timeIntervalSinceNow, 0)
    }

    var isSnoozing: Bool { snoozeUntil != nil }

    /// 本小时已累计离开的秒数
    func awaySecondsThisHour(now: Date = Date()) -> TimeInterval {
        away.awaySeconds(inHourOf: now, now: now)
    }

    /// 本小时是否已达标，因而第 N 分不会提醒
    func isThisHourExempt(now: Date = Date()) -> Bool {
        away.hasBeenAwayEnough(inHourOf: now, now: now)
    }

    // MARK: - 私有：定时与判定

    private func tick() {
        guard phase == .waiting else { return }
        let now = Date()
        stats.rolloverIfNeeded(now: now)

        if let until = snoozeUntil {
            if now >= until {
                // 延后到点时人不在（屏保/锁屏）：不弹，保留延后状态，等回来再弹
                guard !away.isAway else { return }
                snoozeUntil = nil
                fire(now: now)
            }
            return
        }

        guard now >= nextFire else { return }

        let hourStart = away.hourStart(nextFire)

        // 正在屏保 / 锁屏 / 显示器睡眠：不弹（人在外面），交给唤醒后的补提醒逻辑
        if away.isAway {
            lastHandledHour = hourStart
            advance(now: now)
            return
        }

        // 本小时已经离开足够久：静默跳过，不计入任何计数
        away.prune(before: calendar.date(byAdding: .hour, value: -1, to: now) ?? now)
        if away.hasBeenAwayEnough(inHourOf: nextFire, now: now) {
            lastHandledHour = hourStart
            advance(now: now)
            return
        }

        fire(now: now)
    }

    private func fire(now: Date) {
        if !isManualRing {
            lastHandledHour = away.hourStart(nextFire)
            stats.addReminder()
        }
        phase = .ringing
        onRing?()
        onChange?()
    }

    /// 关闭遮罩后的统一收尾：凡是关掉了遮罩，都算本小时的活动被确认
    private func finishRing() {
        if !isManualRing {
            stats.addCompleted()
        }
        isManualRing = false
        phase = .waiting
        snoozeUntil = nil
        nextFire = Schedule.nextFire(after: Date(), config: config, calendar: calendar)
        onChange?()
    }

    /// 静默跳过本小时（免提醒），不计数
    private func advance(now: Date) {
        nextFire = Schedule.nextFire(after: now, config: config, calendar: calendar)
        onChange?()
    }

    /// 唤醒 / 解锁后：够近就立刻补弹一次，否则排到下一个锚点
    private func catchUpOrNext(_ now: Date) -> Date {
        if let anchor = Anchor.thisHour(now, minute: config.anchorMinute, calendar: calendar),
           anchor <= now,
           now.timeIntervalSince(anchor) <= TimeInterval(config.catchUpMinutes) * 60,
           lastHandledHour != away.hourStart(now),
           config.hourIsActive(calendar.component(.hour, from: anchor)),
           !away.hasBeenAwayEnough(inHourOf: now, now: now) {
            return now
        }
        return Schedule.nextFire(after: now, config: config, calendar: calendar)
    }

    // MARK: - 私有：跨启动记住「本小时已处理过」

    private static let lastHandledKey = "runtime.lastHandledHour"

    private func persistLastHandledHour() {
        let defaults = UserDefaults.standard
        if let hour = lastHandledHour {
            defaults.set(hour.timeIntervalSince1970, forKey: Scheduler.lastHandledKey)
        } else {
            defaults.removeObject(forKey: Scheduler.lastHandledKey)
        }
    }

    private static func loadLastHandledHour() -> Date? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: lastHandledKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: lastHandledKey))
    }
}
