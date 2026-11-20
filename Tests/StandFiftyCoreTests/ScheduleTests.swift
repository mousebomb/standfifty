import XCTest
@testable import StandFiftyCore

final class ScheduleTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return calendar.date(from: c)!
    }

    private func next(_ now: Date, config: AppConfig = AppConfig()) -> Date {
        Schedule.nextFire(after: now, config: config, calendar: calendar)
    }

    func test_工作时段内正常锚点() {
        XCTAssertEqual(next(date(2026, 11, 20, 9, 3)), date(2026, 11, 20, 9, 50))
        XCTAssertEqual(next(date(2026, 11, 20, 21, 40)), date(2026, 11, 20, 21, 50))
    }

    func test_还没开工跳到当天开工后第一个锚点() {
        XCTAssertEqual(next(date(2026, 11, 20, 6, 10)), date(2026, 11, 20, 7, 50))
        XCTAssertEqual(next(date(2026, 11, 20, 0, 5)), date(2026, 11, 20, 7, 50))
    }

    func test_收工后跳到次日() {
        XCTAssertEqual(next(date(2026, 11, 20, 22, 30)), date(2026, 11, 21, 7, 50))
        // 21:55 的下一个锚点是 22:50，不在时段内 → 次日
        XCTAssertEqual(next(date(2026, 11, 20, 21, 55)), date(2026, 11, 21, 7, 50))
        XCTAssertEqual(next(date(2026, 11, 20, 23, 59)), date(2026, 11, 21, 7, 50))
    }

    func test_跨月与跨年() {
        XCTAssertEqual(next(date(2026, 11, 30, 23, 10)), date(2026, 12, 1, 7, 50))
        XCTAssertEqual(next(date(2026, 12, 31, 22, 10)), date(2027, 1, 1, 7, 50))
    }

    func test_自定义锚点与时段() {
        var config = AppConfig()
        config.anchorMinute = 25
        config.activeStartHour = 8
        config.activeEndHour = 18
        XCTAssertEqual(next(date(2026, 11, 20, 17, 30), config: config), date(2026, 11, 21, 8, 25))
        XCTAssertEqual(next(date(2026, 11, 20, 7, 59), config: config), date(2026, 11, 20, 8, 25))
    }
}
