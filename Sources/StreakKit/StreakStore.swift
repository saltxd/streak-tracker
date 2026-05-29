import Foundation
import Observation

/// Owns the streak's persisted state and exposes the values the menu bar renders.
///
/// Only the anchor day, the personal-best, and the reset history are persisted
/// (UserDefaults). The visible `currentStreak` is derived from the clock by `refresh()`
/// and is the thing SwiftUI observes.
@Observable
public final class StreakStore {

    /// Days the current streak has run (anchor day = 1). Updated by `refresh()`.
    public private(set) var currentStreak: Int = 0
    /// Longest streak ever reached. Persisted; never goes down on reset.
    public private(set) var longestStreak: Int = 0
    /// The anchor day the count derives from.
    public private(set) var startDay: Date?
    /// Past streaks that ended at a reset, oldest first.
    public private(set) var history: [ResetRecord] = []

    /// The most recent reset, if any.
    public var lastReset: ResetRecord? { history.last }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    private enum Key {
        static let startDay = "streak.startDay"
        static let longest = "streak.longestStreak"
        static let everStarted = "streak.everStarted"
        static let history = "streak.history"
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
        if let data = defaults.data(forKey: Key.history),
           let decoded = try? JSONDecoder().decode([ResetRecord].self, from: data) {
            history = decoded
        }
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

    /// Begin a fresh streak — today reads 1. (Not logged as a slip.)
    public func start(now: Date = Date()) {
        setAnchor(DayMath.today(now, calendar: calendar), now: now)
    }

    /// Backdate the streak to the day it actually began — that day reads 1. A correction,
    /// so it is *not* recorded in reset history.
    public func setStartDate(_ date: Date, now: Date = Date()) {
        setAnchor(calendar.startOfDay(for: date), now: now)
    }

    /// Slipped up — log the broken streak, then today reads 0 and tomorrow starts at 1.
    public func reset(now: Date = Date()) {
        let ended = DayMath.streakValue(startDay: startDay, now: now, calendar: calendar)
        if ended > 0 {
            history.append(ResetRecord(endedOn: calendar.startOfDay(for: now), length: ended))
            saveHistory()
        }
        setAnchor(DayMath.tomorrow(now, calendar: calendar), now: now)
    }

    private func setAnchor(_ anchor: Date, now: Date) {
        startDay = anchor
        defaults.set(anchor, forKey: Key.startDay)
        defaults.set(true, forKey: Key.everStarted)
        refresh(now: now)
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Key.history)
        }
    }
}
