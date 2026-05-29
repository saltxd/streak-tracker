import Foundation
import Observation

/// Owns the streak's persisted state and exposes the values the menu bar renders.
///
/// Only the anchor day and the personal-best are persisted (UserDefaults). The
/// visible `currentStreak` is derived from the clock by `refresh()` and is the
/// thing SwiftUI observes.
@Observable
public final class StreakStore {

    /// Days the current streak has run (anchor day = 1). Updated by `refresh()`.
    public private(set) var currentStreak: Int = 0
    /// Longest streak ever reached. Persisted; never goes down on reset.
    public private(set) var longestStreak: Int = 0
    /// The anchor day the count derives from.
    public private(set) var startDay: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    private enum Key {
        static let startDay = "streak.startDay"
        static let longest = "streak.longestStreak"
        static let everStarted = "streak.everStarted"
    }

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = Date()) {
        self.defaults = defaults
        self.calendar = calendar

        if let stored = defaults.object(forKey: Key.startDay) as? Date {
            startDay = stored
        } else if !defaults.bool(forKey: Key.everStarted) {
            // First-ever launch: begin a streak today so the menu bar reads 1 immediately.
            startDay = DayMath.today(now, calendar: calendar)
            defaults.set(startDay, forKey: Key.startDay)
            defaults.set(true, forKey: Key.everStarted)
        }
        longestStreak = defaults.integer(forKey: Key.longest)
        refresh(now: now)
    }

    /// Recompute the visible streak from the clock and bump the personal best if beaten.
    public func refresh(now: Date = Date()) {
        currentStreak = DayMath.streakValue(startDay: startDay, now: now, calendar: calendar)
        if currentStreak > longestStreak {
            longestStreak = currentStreak
            defaults.set(longestStreak, forKey: Key.longest)
        }
    }

    /// Begin a fresh streak — today reads 1.
    public func start(now: Date = Date()) {
        setAnchor(DayMath.today(now, calendar: calendar), now: now)
    }

    /// Slipped up — today reads 0, tomorrow starts again at 1.
    public func reset(now: Date = Date()) {
        setAnchor(DayMath.tomorrow(now, calendar: calendar), now: now)
    }

    private func setAnchor(_ anchor: Date, now: Date) {
        startDay = anchor
        defaults.set(anchor, forKey: Key.startDay)
        defaults.set(true, forKey: Key.everStarted)
        refresh(now: now)
    }
}
