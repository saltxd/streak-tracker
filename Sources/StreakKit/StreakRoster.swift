import Foundation
import Observation

/// Owns the collection of streaks, the active selection, and persistence.
///
/// Only `StreakRoster` is `@Observable`; the `Streak` elements are pure value types. That is
/// what makes an in-array mutation (or an `activeID` change) fan out to the menu-bar label and
/// the panel — an array of observable *classes* would go stale. The visible counts are derived
/// from the clock by `refresh(_:)` into `counts`, which the views observe.
///
/// State is persisted as **one JSON blob** under a versioned key. The migration from the
/// original single-streak `streak.*` keys runs once in `init`, preserving the user's existing
/// streak byte-for-byte and making it the active one.
@Observable
public final class StreakRoster {

    /// All tracked streaks, in display order.
    public private(set) var streaks: [Streak]
    /// The streak shown in the menu bar and as the panel hero.
    public private(set) var activeID: UUID
    /// Derived current value per streak id — recomputed from the clock by `refresh(_:)`.
    public private(set) var counts: [UUID: Int] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    // MARK: Keys

    private enum Key {
        static let roster = "roster.v1"          // the JSON blob
        static let migrated = "roster.migrated"  // legacy import happened (set LAST)
        // Legacy single-streak keys — read for migration/recovery, never written here.
        static let legacyStartDay = "streak.startDay"
        static let legacyLongest = "streak.longestStreak"
        static let legacyEverStarted = "streak.everStarted"
        static let legacyHistory = "streak.history"
        static let legacyUndoAnchor = "streak.undo.anchor"
        static let legacyUndoResetDay = "streak.undo.resetDay"
        static let legacyUndoLogged = "streak.undo.loggedRecord"
    }

    // One shared coder pair with an explicit, debuggable strategy so encode/decode of the
    // NEW blob can never diverge. (The LEGACY reader below uses the original formats instead.)
    @ObservationIgnored private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    @ObservationIgnored private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    /// The blob actually written to disk. `schemaVersion` lives *inside* the model (not only in
    /// the key name) so the decoder can see it the day a v2 format ships.
    private struct RosterBlob: Codable {
        var schemaVersion: Int
        var streaks: [Streak]
        var activeID: UUID
    }

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = Date()) {
        self.defaults = defaults
        self.calendar = calendar

        let loaded = Self.loadOrMigrate(defaults: defaults, calendar: calendar, now: now)
        self.streaks = loaded.streaks
        self.activeID = loaded.activeID

        // Advance every streak from the clock and persist if anything moved.
        refresh(now: now)
        // For a freshly migrated/created roster, persist the blob even if refresh wasn't dirty,
        // then mark the legacy import done LAST (so a crash mid-migration safely retries).
        if loaded.source != .existing {
            save()
            if loaded.source == .migrated { defaults.set(true, forKey: Key.migrated) }
        }
    }

    // MARK: Loading & migration

    private enum Source { case existing, migrated, fresh }
    private struct Loaded { var streaks: [Streak]; var activeID: UUID; var source: Source }

    private static func loadOrMigrate(defaults: UserDefaults, calendar: Calendar, now: Date) -> Loaded {
        // 1. Existing roster blob. A *decode error* (corrupt/garbage) must NOT be swallowed into
        //    "fresh install" — that would silently reset the visible streak to 0. Fall through to
        //    legacy recovery instead. A valid-but-empty blob is a legitimate deleted-all state.
        if let data = defaults.data(forKey: Key.roster) {
            do {
                let blob = try decoder.decode(RosterBlob.self, from: data)
                let active = blob.streaks.contains { $0.id == blob.activeID }
                    ? blob.activeID
                    : (blob.streaks.first?.id ?? blob.activeID)
                return Loaded(streaks: blob.streaks, activeID: active, source: .existing)
            } catch {
                // corrupt → try to recover from the legacy keys below
            }
        }

        // 2. Migrate / recover from the original single-streak keys.
        if let migrated = migrateLegacy(defaults: defaults, calendar: calendar) {
            return Loaded(streaks: [migrated], activeID: migrated.id, source: .migrated)
        }

        // 3. Genuine first launch: one fresh streak anchored today (reads 0 now, 1 tomorrow).
        let fresh = Streak(name: "Streak", startDay: DayMath.today(now, calendar: calendar))
        return Loaded(streaks: [fresh], activeID: fresh.id, source: .fresh)
    }

    /// Build one `Streak` from the legacy keys, reading **each value in the format the original
    /// code wrote it**: `startDay`/undo dates are raw `NSDate` (`object(forKey:)`), but `history`
    /// was written with a bare `JSONEncoder()` (= `.deferredToDate`), so it gets a default-strategy
    /// decoder. Returns nil when there's no prior single-streak install to migrate.
    private static func migrateLegacy(defaults: UserDefaults, calendar: Calendar) -> Streak? {
        let hasAnchor = defaults.object(forKey: Key.legacyStartDay) != nil
        let everStarted = defaults.bool(forKey: Key.legacyEverStarted)
        guard hasAnchor || everStarted else { return nil }

        let startDay = defaults.object(forKey: Key.legacyStartDay) as? Date
        let longest = defaults.integer(forKey: Key.legacyLongest)

        var history: [ResetRecord] = []
        if let data = defaults.data(forKey: Key.legacyHistory) {
            history = (try? JSONDecoder().decode([ResetRecord].self, from: data)) ?? []
        }

        var undo: UndoSnapshot?
        if let anchor = defaults.object(forKey: Key.legacyUndoAnchor) as? Date,
           let resetDay = defaults.object(forKey: Key.legacyUndoResetDay) as? Date {
            undo = UndoSnapshot(anchor: anchor,
                                resetDay: resetDay,
                                loggedRecord: defaults.bool(forKey: Key.legacyUndoLogged))
        }

        return Streak(name: "Streak", startDay: startDay, longestStreak: longest,
                      history: history, undo: undo)
    }

    // MARK: Derived accessors

    public var activeStreak: Streak? { streaks.first { $0.id == activeID } }
    public var activeCount: Int { counts[activeID] ?? 0 }
    public func count(for id: UUID) -> Int { counts[id] ?? 0 }
    public var isEmpty: Bool { streaks.isEmpty }

    // MARK: Refresh (clock advance) — used by init and the midnight/wake timers

    /// Recompute every streak's derived count, drop stale undo snapshots, and bump each personal
    /// best. Persists only if a streak's *stored* state actually changed. Every streak advances
    /// (not just the active one) so a later switch never shows a stale count.
    public func refresh(now: Date = Date()) {
        var dirty = false
        for i in streaks.indices {
            let before = streaks[i]
            streaks[i].clearStaleUndo(now: now, calendar: calendar)
            streaks[i].bumpLongest(now: now, calendar: calendar)
            if streaks[i] != before { dirty = true }
        }
        recomputeCounts(now: now)
        if dirty { save() }
    }

    private func recomputeCounts(now: Date) {
        var next: [UUID: Int] = [:]
        for s in streaks { next[s.id] = s.currentStreak(now: now, calendar: calendar) }
        counts = next
    }

    // MARK: Collection mutations (call sites are Button actions / post-NSAlert — never in a body)

    /// Make `id` the active (menu bar + hero) streak.
    public func setActive(_ id: UUID) {
        guard streaks.contains(where: { $0.id == id }) else { return }
        activeID = id
        save()
    }

    /// Add a new streak anchored today. Does NOT change the active selection, so the menu bar
    /// keeps showing the current streak. Returns the new id.
    @discardableResult
    public func add(name: String, now: Date = Date()) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let streak = Streak(name: trimmed.isEmpty ? "New Streak" : trimmed,
                            startDay: DayMath.today(now, calendar: calendar))
        streaks.append(streak)
        recomputeCounts(now: now)
        save()
        return streak.id
    }

    /// Delete a streak (loses its history). Deleting the active one reassigns active to the first
    /// remaining; deleting the last leaves an empty roster (the panel shows its empty state).
    public func remove(_ id: UUID, now: Date = Date()) {
        guard let i = index(of: id) else { return }
        let wasActive = id == activeID
        streaks.remove(at: i)
        if wasActive, let first = streaks.first { activeID = first.id }
        recomputeCounts(now: now)
        save()
    }

    /// Rename a streak. Empty/whitespace-only names are ignored (validated at the dialog too).
    public func rename(_ id: UUID, to name: String) {
        guard let i = index(of: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        streaks[i].name = trimmed
        save()
    }

    public func reset(_ id: UUID, now: Date = Date()) {
        guard let i = index(of: id) else { return }
        streaks[i].reset(now: now, calendar: calendar)
        recomputeCounts(now: now)
        save()
    }

    public func setStartDate(_ id: UUID, _ date: Date, now: Date = Date()) {
        guard let i = index(of: id) else { return }
        streaks[i].setStartDate(date, now: now, calendar: calendar)
        recomputeCounts(now: now)
        save()
    }

    public func undoReset(_ id: UUID, now: Date = Date()) {
        guard let i = index(of: id) else { return }
        streaks[i].undoReset(now: now, calendar: calendar)
        recomputeCounts(now: now)
        save()
    }

    public func canUndoReset(_ id: UUID, now: Date = Date()) -> Bool {
        guard let i = index(of: id) else { return false }
        return streaks[i].canUndoReset(now: now, calendar: calendar)
    }

    // MARK: Persistence

    private func index(of id: UUID) -> Int? { streaks.firstIndex { $0.id == id } }

    private func save() {
        let blob = RosterBlob(schemaVersion: 1, streaks: streaks, activeID: activeID)
        if let data = try? Self.encoder.encode(blob) {
            defaults.set(data, forKey: Key.roster)
        }
    }
}
