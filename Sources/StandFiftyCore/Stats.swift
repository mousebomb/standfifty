import Foundation

/// 今日三项计数：提醒 / 完成 / 跳过。只保留当天，跨日自动清零。
public final class Stats {

    public private(set) var reminders = 0
    public private(set) var completed = 0
    public private(set) var skipped = 0

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var dayKey: String

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = Date()) {
        self.defaults = defaults
        self.calendar = calendar
        self.dayKey = Stats.key(for: now, calendar: calendar)
        load()
    }

    public func addReminder() { bump(\.reminders) }
    public func addCompleted() { bump(\.completed) }
    public func addSkipped() { bump(\.skipped) }

    /// 跨日检查，返回是否发生了清零
    @discardableResult
    public func rolloverIfNeeded(now: Date = Date()) -> Bool {
        let key = Stats.key(for: now, calendar: calendar)
        guard key != dayKey else { return false }
        dayKey = key
        reminders = 0
        completed = 0
        skipped = 0
        persist()
        return true
    }

    // MARK: - 私有

    private func bump(_ path: ReferenceWritableKeyPath<Stats, Int>) {
        rolloverIfNeeded()
        self[keyPath: path] += 1
        persist()
    }

    private func load() {
        let dict = defaults.dictionary(forKey: dayKey) ?? [:]
        reminders = dict["reminders"] as? Int ?? 0
        completed = dict["completed"] as? Int ?? 0
        skipped = dict["skipped"] as? Int ?? 0
    }

    private func persist() {
        defaults.set(["reminders": reminders, "completed": completed, "skipped": skipped], forKey: dayKey)
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "stats.%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
