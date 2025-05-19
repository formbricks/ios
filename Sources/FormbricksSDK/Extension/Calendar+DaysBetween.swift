import Foundation

extension Calendar {
    /// Returns the number of days between two dates.
    func numberOfDaysBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)
        
        guard let day = numberOfDays.day else { return 0 }
        return abs(day + 1)
    }
}
