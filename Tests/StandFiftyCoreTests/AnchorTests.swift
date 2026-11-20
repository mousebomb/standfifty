import XCTest
@testable import StandFiftyCore

final class AnchorTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 构造一个指定日期时刻
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return calendar.date(from: c)!
    }

    private func next(_ now: Date, minute: Int = 50) -> Date {
        Anchor.next(after: now, minute: minute, calendar: calendar)
    }

    func test_常规_0903_到_0950() {
        XCTAssertEqual(next(date(2026, 11, 20, 9, 3)), date(2026, 11, 20, 9, 50))
    }

    func test_已过锚点_0955_到_1050() {
        XCTAssertEqual(next(date(2026, 11, 20, 9, 55)), date(2026, 11, 20, 10, 50))
    }

    func test_正好命中_严格大于防死循环() {
        XCTAssertEqual(next(date(2026, 11, 20, 9, 50, 0)), date(2026, 11, 20, 10, 50))
    }

    func test_跨天_2355_到次日0050() {
        XCTAssertEqual(next(date(2026, 11, 20, 23, 55)), date(2026, 11, 21, 0, 50))
    }

    func test_工作时段起点_0700_到_0750() {
        XCTAssertEqual(next(date(2026, 11, 20, 7, 0)), date(2026, 11, 20, 7, 50))
    }

    func test_锚点零点_0050_到_0150() {
        XCTAssertEqual(next(date(2026, 11, 21, 0, 50), minute: 50), date(2026, 11, 21, 1, 50))
    }

    func test_自定义锚点_0019_到_0020() {
        XCTAssertEqual(next(date(2026, 11, 20, 0, 19), minute: 20), date(2026, 11, 20, 0, 20))
    }

    func test_thisHour_返回本小时锚点() {
        XCTAssertEqual(
            Anchor.thisHour(date(2026, 11, 20, 9, 55), minute: 50, calendar: calendar),
            date(2026, 11, 20, 9, 50)
        )
    }
}

final class AwayTrackerTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return calendar.date(from: c)!
    }

    func test_单小时内累计离开() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        tracker.beginAway(at: date(2026, 11, 20, 9, 10))
        tracker.endAway(at: date(2026, 11, 20, 9, 11))

        XCTAssertEqual(tracker.awaySeconds(inHourOf: date(2026, 11, 20, 9, 30)), 60, accuracy: 0.001)
        XCTAssertTrue(tracker.hasBeenAwayEnough(inHourOf: date(2026, 11, 20, 9, 30)))
    }

    func test_不足门槛不算已活动() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        tracker.beginAway(at: date(2026, 11, 20, 9, 10))
        tracker.endAway(at: date(2026, 11, 20, 9, 10, 20))

        XCTAssertFalse(tracker.hasBeenAwayEnough(inHourOf: date(2026, 11, 20, 9, 50)))
    }

    func test_多次离开累加() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        tracker.beginAway(at: date(2026, 11, 20, 9, 5))
        tracker.endAway(at: date(2026, 11, 20, 9, 5, 30))
        tracker.beginAway(at: date(2026, 11, 20, 9, 30))
        tracker.endAway(at: date(2026, 11, 20, 9, 30, 40))

        XCTAssertEqual(tracker.awaySeconds(inHourOf: date(2026, 11, 20, 9, 40)), 70, accuracy: 0.001)
    }

    func test_跨整点按重叠分账() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        // 09:49 -> 10:05：09 点 660 秒（11 分钟），10 点 300 秒（5 分钟）
        tracker.beginAway(at: date(2026, 11, 20, 9, 49))
        tracker.endAway(at: date(2026, 11, 20, 10, 5))

        XCTAssertEqual(tracker.awaySeconds(inHourOf: date(2026, 11, 20, 9, 51)), 660, accuracy: 0.001)
        XCTAssertEqual(tracker.awaySeconds(inHourOf: date(2026, 11, 20, 10, 1)), 300, accuracy: 0.001)
    }

    func test_未闭合区间实时计入() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        tracker.beginAway(at: date(2026, 11, 20, 9, 48))
        let seconds = tracker.awaySeconds(inHourOf: date(2026, 11, 20, 9, 50), now: date(2026, 11, 20, 9, 50))
        XCTAssertEqual(seconds, 120, accuracy: 0.001)
        XCTAssertTrue(tracker.isAway)
    }

    func test_重复begin不重置起点() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        tracker.beginAway(at: date(2026, 11, 20, 9, 10))
        tracker.beginAway(at: date(2026, 11, 20, 9, 40))
        tracker.endAway(at: date(2026, 11, 20, 9, 11))
        XCTAssertEqual(tracker.awaySeconds(inHourOf: date(2026, 11, 20, 9, 30)), 60, accuracy: 0.001)
    }

    func test_prune清理旧小时() {
        let tracker = AwayTracker(threshold: 60, calendar: calendar)
        tracker.beginAway(at: date(2026, 11, 20, 8, 10))
        tracker.endAway(at: date(2026, 11, 20, 8, 11))
        tracker.prune(before: date(2026, 11, 20, 9, 5))
        XCTAssertEqual(tracker.awaySeconds(inHourOf: date(2026, 11, 20, 8, 30)), 0, accuracy: 0.001)
    }
}

final class ConfigTests: XCTestCase {

    func test_默认值() {
        let c = AppConfig()
        XCTAssertEqual(c.anchorMinute, 50)
        XCTAssertEqual(c.restSeconds, 60)
        XCTAssertEqual(c.awayThresholdSeconds, 60)
        XCTAssertEqual(c.activeStartHour, 7)
        XCTAssertEqual(c.activeEndHour, 22)
        XCTAssertTrue(c.hourIsActive(7))
        XCTAssertTrue(c.hourIsActive(21))
        XCTAssertFalse(c.hourIsActive(22))
        XCTAssertFalse(c.hourIsActive(6))
    }

    func test_越界值收敛() {
        var c = AppConfig()
        c.anchorMinute = 99
        c.restSeconds = 0
        c.activeEndHour = 30
        let n = c.normalized()
        XCTAssertEqual(n.anchorMinute, 59)
        XCTAssertEqual(n.restSeconds, 5)
        XCTAssertEqual(n.activeEndHour, 24)
    }
}
