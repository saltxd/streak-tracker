import Foundation
import Observation

/// Owns the streak's persisted state and exposes the values the menu bar renders.
///
/// Only the anchor day, the personal-best, the reset history, and a small same-day
/// undo snapshot are persisted (UserDefaults). The visible `currentStreak` is derived
/// from the clock by `refresh()` and is the thing SwiftUI observes.
@Observable
public final class StreakStore {

    /// Days the current streak has run (anchor day = 0). Updated by `refresh()`.
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
        // Same-day undo snapshot of the streak that was just reset.
        static let undoAnchor = "streak.undo.anchor"      // previous startDay
        static let undoResetDay = "streak.undo.resetDay"  // calendar day the reset happened
        static let undoLoggedRecord = "streak.undo.loggedRecord" // whether reset appended history
    }

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = Date()) {
        self.defaults = defaults
        self.calendar = calendar

        if let stored = defaults.object(forKey: Key.startDay) as? Date {
            startDay = stored
        } else if !defaults.bool(forKey: Key.everStarted) {
            // First-ever launch: begin a streak today (reads 0 now, 1 at the next midnight).
            startDay = DayMath.today(now, calendar: calendar)
            defaults.set(startDay, forKey: Key.startDay)
            defaults.set(true, forKey: Key.everStarted)
        }
        longestStreak = defaults.integer(forKey: Key.longest)
        if let data = defaults.data(forKey: Key.history),
           let decoded = try? JSONDecoder().decode([ResetRecord].self, from: data) {
            history = decoded
        }
        // Drop a stale undo snapshot (from a previous day) so it never resurfaces.
        if let resetDay = defaults.object(forKey: Key.undoResetDay) as? Date,
           !calendar.isDate(resetDay, inSameDayAs: now) {
            clearUndo()
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

    /// Begin a fresh streak — today reads 0, then 1 at the next midnight. (Not a slip.)
    public func start(now: Date = Date()) {
        clearUndo()
        setAnchor(DayMath.today(now, calendar: calendar), now: now)
    }

    /// Backdate the streak to the day it actually began — that day reads 0, and each full
    /// day since adds 1. A correction, so it is *not* recorded in reset history.
    public func setStartDate(_ date: Date, now: Date = Date()) {
        clearUndo()
        setAnchor(calendar.startOfDay(for: date), now: now)
    }

    /// Slipped up — snapshot the streak for same-day undo, log the broken streak, then
    /// today reads 0 and tomorrow starts at 1.
    public func reset(now: Date = Date()) {
        let previousAnchor = startDay
        let ended = DayMath.streakValue(startDay: startDay, now: now, calendar: calendar)
        let logged = ended > 0
        if logged {
            history.append(ResetRecord(endedOn: calendar.startOfDay(for: now), length: ended))
            saveHistory()
        }
        // Stash a one-step undo so a misclick can be recovered the same day.
        if let previousAnchor {
            defaults.set(previousAnchor, forKey: Key.undoAnchor)
            defaults.set(calendar.startOfDay(for: now), forKey: Key.undoResetDay)
            defaults.set(logged, forKey: Key.undoLoggedRecord)
        }
        setAnchor(DayMath.today(now, calendar: calendar), now: now)
    }

    /// True only on the same calendar day as the most recent reset — i.e. a fresh misclick
    /// is recoverable, but yesterday's reset is final.
    public func canUndoReset(now: Date = Date()) -> Bool {
        guard defaults.object(forKey: Key.undoAnchor) is Date,
              let resetDay = defaults.object(forKey: Key.undoResetDay) as? Date else { return false }
        return calendar.isDate(resetDay, inSameDayAs: now)
    }

    /// Restore the streak that the most recent (same-day) reset broke: re-anchor to the old
    /// start day and remove the history entry the reset added.
    public func undoReset(now: Date = Date()) {
        guard canUndoReset(now: now),
              let previousAnchor = defaults.object(forKey: Key.undoAnchor) as? Date else { return }
        if defaults.bool(forKey: Key.undoLoggedRecord), !history.isEmpty {
            history.removeLast()
            saveHistory()
        }
        clearUndo()
        setAnchor(previousAnchor, now: now)
    }

    private func clearUndo() {
        defaults.removeObject(forKey: Key.undoAnchor)
        defaults.removeObject(forKey: Key.undoResetDay)
        defaults.removeObject(forKey: Key.undoLoggedRecord)
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
