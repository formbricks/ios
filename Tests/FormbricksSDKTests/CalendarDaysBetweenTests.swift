import XCTest
@testable import FormbricksSDK

final class CalendarDaysBetweenTests: XCTestCase {
    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps) ?? Date()
    }

    func testSameDayReturnsZero() {
        let from = makeDate(year: 2025, month: 1, day: 15, hour: 10, minute: 30)
        let to = makeDate(year: 2025, month: 1, day: 15, hour: 22, minute: 15)
        let days = Calendar.current.numberOfDaysBetween(from, and: to)
        XCTAssertEqual(days, 0)
    }

    func testNextDayReturnsOne() {
        let from = makeDate(year: 2025, month: 1, day: 15, hour: 10)
        let to = makeDate(year: 2025, month: 1, day: 16, hour: 9)
        let days = Calendar.current.numberOfDaysBetween(from, and: to)
        XCTAssertEqual(days, 1)
    }

    func testMultipleDays() {
        let from = makeDate(year: 2025, month: 1, day: 10, hour: 10)
        let to = makeDate(year: 2025, month: 1, day: 13, hour: 9)
        let days = Calendar.current.numberOfDaysBetween(from, and: to)
        XCTAssertEqual(days, 3)
    }

    func testReverseOrderClampsToZero() {
        let from = makeDate(year: 2025, month: 1, day: 20, hour: 12)
        let to = makeDate(year: 2025, month: 1, day: 18, hour: 12)
        let days = Calendar.current.numberOfDaysBetween(from, and: to)
        XCTAssertEqual(days, 0)
    }

    func testAcrossMidnightCountsAsOne() {
        let from = makeDate(year: 2025, month: 3, day: 10, hour: 23, minute: 59)
        let to = makeDate(year: 2025, month: 3, day: 11, hour: 0, minute: 1)
        let days = Calendar.current.numberOfDaysBetween(from, and: to)
        XCTAssertEqual(days, 1)
    }
}


