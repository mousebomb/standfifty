import Foundation

/// 配置项，落 UserDefaults。所有值在读写时都会做范围收敛。
public struct AppConfig: Equatable {
    /// 每小时的第几分钟提醒（默认 50，对齐 Apple Watch 站立提醒）
    public var anchorMinute = 50
    /// 遮罩需要「净离开键盘」多少秒才自动关闭
    public var restSeconds = 60
    /// 一个自然小时内累计离开多少秒，即视为「已活动过」，该小时不再提醒
    public var awayThresholdSeconds = 60
    /// 点「延后」后再等多少秒
    public var snoozeSeconds = 60
    /// 工作时段起（含），默认 07:00
    public var activeStartHour = 7
    /// 工作时段止（不含），默认 22:00
    public var activeEndHour = 22
    /// 醒来后距锚点不超过多少分钟就补弹一次
    public var catchUpMinutes = 15

    public init() {}

    /// 工作时段是否覆盖全天
    public var isAlwaysActive: Bool { activeStartHour == activeEndHour }

    public func hourIsActive(_ hour: Int) -> Bool {
        if isAlwaysActive { return true }
        return hour >= activeStartHour && hour < activeEndHour
    }

    public func normalized() -> AppConfig {
        var c = self
        c.anchorMinute = min(max(anchorMinute, 0), 59)
        c.restSeconds = min(max(restSeconds, 5), 3600)
        c.awayThresholdSeconds = min(max(awayThresholdSeconds, 5), 7200)
        c.snoozeSeconds = min(max(snoozeSeconds, 10), 3600)
        c.activeStartHour = min(max(activeStartHour, 0), 23)
        c.activeEndHour = min(max(activeEndHour, 0), 24)
        c.catchUpMinutes = min(max(catchUpMinutes, 0), 120)
        return c
    }

    // MARK: - 持久化

    private enum Key {
        static let prefix = "config."
        static let anchorMinute = prefix + "anchorMinute"
        static let restSeconds = prefix + "restSeconds"
        static let awayThresholdSeconds = prefix + "awayThresholdSeconds"
        static let snoozeSeconds = prefix + "snoozeSeconds"
        static let activeStartHour = prefix + "activeStartHour"
        static let activeEndHour = prefix + "activeEndHour"
        static let catchUpMinutes = prefix + "catchUpMinutes"
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppConfig {
        var c = AppConfig()
        c.anchorMinute = read(defaults, Key.anchorMinute, c.anchorMinute)
        c.restSeconds = read(defaults, Key.restSeconds, c.restSeconds)
        c.awayThresholdSeconds = read(defaults, Key.awayThresholdSeconds, c.awayThresholdSeconds)
        c.snoozeSeconds = read(defaults, Key.snoozeSeconds, c.snoozeSeconds)
        c.activeStartHour = read(defaults, Key.activeStartHour, c.activeStartHour)
        c.activeEndHour = read(defaults, Key.activeEndHour, c.activeEndHour)
        c.catchUpMinutes = read(defaults, Key.catchUpMinutes, c.catchUpMinutes)
        return c.normalized()
    }

    public func save(to defaults: UserDefaults = .standard) {
        let c = normalized()
        defaults.set(c.anchorMinute, forKey: Key.anchorMinute)
        defaults.set(c.restSeconds, forKey: Key.restSeconds)
        defaults.set(c.awayThresholdSeconds, forKey: Key.awayThresholdSeconds)
        defaults.set(c.snoozeSeconds, forKey: Key.snoozeSeconds)
        defaults.set(c.activeStartHour, forKey: Key.activeStartHour)
        defaults.set(c.activeEndHour, forKey: Key.activeEndHour)
        defaults.set(c.catchUpMinutes, forKey: Key.catchUpMinutes)
    }

    private static func read(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.integer(forKey: key)
    }
}
