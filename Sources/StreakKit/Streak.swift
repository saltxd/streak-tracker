import Foundation

/// One tracked streak: a name plus the persisted state the count derives from.
///
/// A **pure value type** — no `UserDefaults`, no UI. The displayed `currentStreak` is never
/// stored; it is derived from the clock (completed days since `startDay`) by `currentStreak`.
/// All the slip/undo/backdate rules live here as `mutating` funcs that take `now`, so the
/// behaviour is unit-checkable without any persistence. The owning `StreakRoster` persists
/// these and exposes the observable values the menu bar and panel render.
///
/// Decoding is deliberately tolerant (missing fields fall back to defaults) so a blob written
/// by an older or newer build still loads instead of throwing.
public struct Streak: Codable, Identifiable, Equatable, Sendable {

    /// Stable identity used for the active selection and `ForEach`.
    public let id: UUID
    /// User-facing label shown in the hero caption and the list row.
    public var name: String
    /// The anchor day the count derives from (anchor reads 0, each full day since adds 1).
    public var startDay: Date?
    /// Longest streak ever reached. Never goes down on reset.
    public var longestStreak: Int
    /// Past streaks that ended at a reset, oldest first.
    public var history: [ResetRecord]
    /// Same-day undo snapshot of the streak this one's most recent reset broke.
    public var undo: UndoSnapshot?

    public init(id: UUID = UUID(),
                name: String,
                startDay: Date?,
                longestStreak: Int = 0,
                history: [ResetRecord] = [],
                undo: UndoSnapshot? = nil) {
        self.id = id
        self.name = name
        self.startDay = startDay
        self.longestStreak = longestStreak
        self.history = history
        self.undo = undo
    }

    /// The most recent reset, if any.
    public var lastReset: ResetRecord? { history.last }

    // MARK: Derived value

    /// The displayed streak: completed days since the anchor, floored at 0.
    public func currentStreak(now: Date, calendar: Calendar) -> Int {
        DayMath.streakValue(startDay: startDay, now: now, calendar: calendar)
    }

    // MARK: Mutations (same rules as the original single-streak store, but pure)

    /// Bump the personal best if the current value beats it. Idempotent.
    public mutating func bumpLongest(now: Date, calendar: Calendar) {
        let current = currentStreak(now: now, calendar: calendar)
        if current > longestStreak { longestStreak = current }
    }

    /// Drop an undo snapshot left over from a previous day so it never resurfaces.
    public mutating func clearStaleUndo(now: Date, calendar: Calendar) {
        if let undo, !calendar.isDate(undo.resetDay, inSameDayAs: now) { self.undo = nil }
    }

    /// Backdate the streak to the day it actually began — a correction, so it is *not* logged.
    public mutating func setStartDate(_ date: Date, now: Date, calendar: Calendar) {
        undo = nil
        setAnchor(calendar.startOfDay(for: date), now: now, calendar: calendar)
    }

    /// Slipped up — log the broken streak, stash a same-day undo snapshot, then today reads 0.
    public mutating func reset(now: Date, calendar: Calendar) {
        let previousAnchor = startDay
        let ended = currentStreak(now: now, calendar: calendar)
        let logged = ended > 0
        if logged {
            history.append(ResetRecord(endedOn: calendar.startOfDay(for: now), length: ended))
        }
        // Stash a one-step undo so a misclick can be recovered the same day (only when there
        // was an anchor to restore — mirrors the original store).
        if let previousAnchor {
            undo = UndoSnapshot(anchor: previousAnchor,
                                resetDay: calendar.startOfDay(for: now),
                                loggedRecord: logged)
        }
        setAnchor(DayMath.today(now, calendar: calendar), now: now, calendar: calendar)
    }

    /// True only on the same calendar day as this streak's most recent reset.
    public func canUndoReset(now: Date, calendar: Calendar) -> Bool {
        guard let undo else { return false }
        return calendar.isDate(undo.resetDay, inSameDayAs: now)
    }

    /// Restore the streak the most recent (same-day) reset broke: re-anchor to the old start
    /// day and remove the history entry that reset added.
    public mutating func undoReset(now: Date, calendar: Calendar) {
        guard canUndoReset(now: now, calendar: calendar), let undo else { return }
        if undo.loggedRecord, !history.isEmpty { history.removeLast() }
        self.undo = nil
        setAnchor(undo.anchor, now: now, calendar: calendar)
    }

    private mutating func setAnchor(_ anchor: Date, now: Date, calendar: Calendar) {
        startDay = anchor
        bumpLongest(now: now, calendar: calendar)
    }

    // MARK: Tolerant decoding

    private enum CodingKeys: String, CodingKey { case id, name, startDay, longestStreak, history, undo }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Streak"
        startDay = try? c.decode(Date.self, forKey: .startDay)
        longestStreak = (try? c.decode(Int.self, forKey: .longestStreak)) ?? 0
        history = (try? c.decode([ResetRecord].self, forKey: .history)) ?? []
        undo = try? c.decode(UndoSnapshot.self, forKey: .undo)
    }
}

/// A one-step, same-day snapshot of the streak a reset broke, so a misclick is recoverable.
public struct UndoSnapshot: Codable, Equatable, Sendable {
    /// The `startDay` the streak had before the reset.
    public let anchor: Date
    /// The calendar day (start-of-day) the reset happened.
    public let resetDay: Date
    /// Whether that reset appended a record to history (so undo knows to remove it).
    public let loggedRecord: Bool

    public init(anchor: Date, resetDay: Date, loggedRecord: Bool) {
        self.anchor = anchor
        self.resetDay = resetDay
        self.loggedRecord = loggedRecord
    }
}
