import Foundation

/// Calendar-day arithmetic for the streak counter.
///
/// The streak is never stored as a number you tick up. Instead we store an *anchor
/// day* and derive the count from the wall clock. That makes the count correct even
/// when the app was closed for days, survives reboots, and handles DST / timezone
/// shifts because everything is computed in whole calendar days, not 24-hour chunks.
///
/// The model is **completed days since the anchor**: the anchor day itself reads 0, and
/// each full calendar day that passes adds 1. So starting today shows 0 and ticks to 1
/// at the next midnight — consistent with a reset, which also lands on 0 for that day.
public enum DayMath {

    /// Whole calendar days from `start` to `now`, comparing start-of-day to start-of-day.
    /// Positive when `now` is a later calendar day, negative when earlier.
    public static func dayCount(from start: Date, to now: Date, calendar: Calendar = .current) -> Int {
        let s = calendar.startOfDay(for: start)
        let n = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: s, to: n).day ?? 0
    }

    /// The displayed streak: completed days since the anchor, floored at 0 so a clock set
    /// backwards (or an anchor in the future) never shows a negative.
    public static func streakValue(startDay: Date?, now: Date, calendar: Calendar = .current) -> Int {
        guard let startDay else { return 0 }
        return max(0, dayCount(from: startDay, to: now, calendar: calendar))
    }

    /// Anchor for the start of a streak (fresh start or a reset): the count reads 0 today
    /// and becomes 1 at the next midnight.
    public static func today(_ now: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    /// The next local midnight strictly after `now` — when the displayed number rolls over.
    public static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
    }
}
