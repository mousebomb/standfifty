import Foundation

/// 记录「离开电脑」的时间区间（屏保 / 锁屏 / 显示器睡眠），并按自然小时分摊秒数。
/// 跨整点的离开会按与各小时的重叠时长分别记账。
public final class AwayTracker {

    /// 一个自然小时内累计离开多少秒算「本小时已活动过」
    public var threshold: TimeInterval

    private let calendar: Calendar
    private var openStart: Date?
    /// key = 该小时的整点时刻
    private var settled: [Date: TimeInterval] = [:]

    public init(threshold: TimeInterval = 60, calendar: Calendar = .current) {
        self.threshold = threshold
        self.calendar = calendar
    }

    /// 当前是否处于离开状态（屏保中 / 锁屏 / 显示器睡眠）
    public var isAway: Bool { openStart != nil }

    public func hourStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// 打开一个离开区间；重复调用不会重置起点
    public func beginAway(at date: Date = Date()) {
        guard openStart == nil else { return }
        openStart = date
    }

    /// 闭合离开区间，把时长按与各自然小时的重叠分账
    public func endAway(at date: Date = Date()) {
        guard let start = openStart else { return }
        openStart = nil
        guard date > start else { return }
        settle(from: start, to: date)
    }

    /// 某个自然小时内已累计的离开秒数（包含正在进行、尚未闭合的区间）
    public func awaySeconds(inHourOf date: Date, now: Date = Date()) -> TimeInterval {
        let start = hourStart(date)
        var total = settled[start] ?? 0
        if let open = openStart, now > open {
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: start) ?? now
            let overlap = min(now, hourEnd).timeIntervalSince(max(open, start))
            if overlap > 0 { total += overlap }
        }
        return total
    }

    /// 该小时是否已达到「已活动」门槛
    public func hasBeenAwayEnough(inHourOf date: Date, now: Date = Date()) -> Bool {
        awaySeconds(inHourOf: date, now: now) >= threshold
    }

    /// 清理过期小时数据（保留 `date` 所在小时及之后）
    public func prune(before date: Date) {
        let keepFrom = hourStart(date)
        settled = settled.filter { $0.key >= keepFrom }
    }
}

// MARK: - 私有

private extension AwayTracker {
    /// 把 [start, end] 按自然小时切段累加
    func settle(from start: Date, to end: Date) {
        var cursor = start
        while cursor < end {
            let hour = hourStart(cursor)
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hour) ?? end
            let segmentEnd = min(end, hourEnd)
            settled[hour, default: 0] += segmentEnd.timeIntervalSince(cursor)
            cursor = segmentEnd
        }
    }
}
