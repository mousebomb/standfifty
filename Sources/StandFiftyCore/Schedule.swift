import Foundation

/// 排期：在「每小时第 N 分钟」这个墙钟规则之上，叠加工作时段过滤。
/// 非工作时段不提醒，直接跳到下一个工作时段内的锚点。
public enum Schedule {

    public static func nextFire(after now: Date, config: AppConfig, calendar: Calendar = .current) -> Date {
        let c = config.normalized()
        var cursor = now
        for _ in 0..<5 {
            let candidate = Anchor.next(after: cursor, minute: c.anchorMinute, calendar: calendar)
            if c.hourIsActive(calendar.component(.hour, from: candidate)) {
                return candidate
            }

            guard let dayStart = calendar.dateInterval(of: .day, for: candidate)?.start else {
                return candidate
            }
            if calendar.component(.hour, from: candidate) >= c.activeEndHour {
                // 已过收工时间：跳到次日 0 点前，下一轮会落到次日开工锚点
                cursor = (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? candidate).addingTimeInterval(-1)
            } else {
                // 还没开工：cursor 推到当天开工时刻之前
                let startOfDay = calendar.date(bySettingHour: c.activeStartHour, minute: 0, second: 0, of: candidate) ?? candidate
                cursor = startOfDay.addingTimeInterval(-1)
            }
        }
        // 兜底（例如起止小时配置异常）
        return Anchor.next(after: now, minute: c.anchorMinute, calendar: calendar)
    }
}
