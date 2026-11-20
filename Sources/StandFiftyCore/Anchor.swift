import Foundation

/// 锚点计算：把「每小时第 N 分钟」这种墙钟规则算成具体时刻。
/// 全项目唯一有边界坑的地方，先写测试再写实现。
public enum Anchor {

    /// 返回严格晚于 `now` 的下一个「每小时第 minute 分钟」时刻。
    /// 用 Calendar 做日期运算，避免跨天 / 夏令时漂移。
    public static func next(after now: Date, minute: Int, calendar: Calendar = .current) -> Date {
        let targetMinute = normalize(minute)
        // 最多向后看 26 小时，足够覆盖任何跨天 / 夏令时边界
        for offset in 0...26 {
            guard let hourDate = calendar.date(byAdding: .hour, value: offset, to: now) else { continue }
            let hour = calendar.component(.hour, from: hourDate)
            // 夏令时前跳会导致该时刻不存在，bySettingHour 返回 nil，跳过即可
            guard let candidate = calendar.date(bySettingHour: hour, minute: targetMinute, second: 0, of: hourDate) else {
                continue
            }
            if candidate > now { return candidate }
        }
        // 理论不可达，兜底
        return now.addingTimeInterval(3600)
    }

    /// 当前自然小时内的锚点时刻（不判断是否已过）
    public static func thisHour(_ now: Date, minute: Int, calendar: Calendar = .current) -> Date? {
        let hour = calendar.component(.hour, from: now)
        return calendar.date(bySettingHour: hour, minute: normalize(minute), second: 0, of: now)
    }

    private static func normalize(_ minute: Int) -> Int {
        min(max(minute, 0), 59)
    }
}
