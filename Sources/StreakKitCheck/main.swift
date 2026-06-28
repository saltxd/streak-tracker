import Foundation
import StreakKit

// A tiny runnable test harness. XCTest / the Testing framework aren't available under
// Command Line Tools, so we assert in plain code and exit non-zero on any failure.
// Run with:  swift run StreakKitCheck
//
// Model under test: **completed days since the anchor** — the anchor day reads 0 and each
// full calendar day since adds 1. Start and reset both land on 0 for "today". Streaks are now
// a collection (StreakRoster) of pure value-type `Streak`s, migrated from the original
// single-streak `streak.*` UserDefaults keys.

var failures = 0
@MainActor func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("  ✓ \(name)")
    } else {
        print("  ✗ \(name)")
        failures += 1
    }
}

// Fixed gregorian calendar in a DST-observing zone so day math is deterministic.
let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Denver")!
    return c
}()
func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
    var dc = DateComponents()
    dc.year = y; dc.month = m; dc.day = day; dc.hour = h
    return cal.date(from: dc)!
}
func day(_ y: Int, _ m: Int, _ d2: Int) -> Date { cal.startOfDay(for: d(y, m, d2)) }

print("DayMath (completed-days model):")
let may29 = cal.startOfDay(for: d(2026, 5, 29))
check("anchor day reads 0",
      DayMath.streakValue(startDay: may29, now: d(2026, 5, 29), calendar: cal) == 0)
check("next day reads 1",
      DayMath.streakValue(startDay: may29, now: d(2026, 5, 30), calendar: cal) == 1)
check("DayMath.today is start-of-day anchor",
      DayMath.today(d(2026, 5, 29), calendar: cal) == may29)
check("anchor today → 0 today, 1 tomorrow",
      DayMath.streakValue(startDay: DayMath.today(d(2026, 5, 29), calendar: cal), now: d(2026, 5, 29), calendar: cal) == 0
      && DayMath.streakValue(startDay: DayMath.today(d(2026, 5, 29), calendar: cal), now: d(2026, 5, 30), calendar: cal) == 1)
check("clock set backwards floors at 0",
      DayMath.streakValue(startDay: may29, now: d(2026, 5, 25), calendar: cal) == 0)
check("DST spring-forward counts 2 calendar days",
      DayMath.streakValue(startDay: cal.startOfDay(for: d(2026, 3, 7)), now: d(2026, 3, 9), calendar: cal) == 2)
check("nil start is 0",
      DayMath.streakValue(startDay: nil, now: d(2026, 5, 29), calendar: cal) == 0)
check("count across month boundary",
      DayMath.streakValue(startDay: may29, now: d(2026, 6, 4), calendar: cal) == 6)

print("Streak (pure value-type logic):")
var s1 = Streak(name: "A", startDay: day(2026, 5, 29))
check("anchor today reads 0", s1.currentStreak(now: d(2026, 5, 29), calendar: cal) == 0)
check("start then 2 days later reads 2", s1.currentStreak(now: d(2026, 5, 31), calendar: cal) == 2)

var s2 = Streak(name: "B", startDay: day(2026, 5, 1))
check("5-day streak", s2.currentStreak(now: d(2026, 5, 6), calendar: cal) == 5)
s2.reset(now: d(2026, 5, 6), calendar: cal)
check("reset reads 0 today", s2.currentStreak(now: d(2026, 5, 6), calendar: cal) == 0)
check("reset reads 1 tomorrow", s2.currentStreak(now: d(2026, 5, 7), calendar: cal) == 1)

var s3 = Streak(name: "C", startDay: day(2026, 5, 29))
s3.bumpLongest(now: d(2026, 6, 8), calendar: cal)
check("10-day streak", s3.currentStreak(now: d(2026, 6, 8), calendar: cal) == 10)
check("longest tracks 10", s3.longestStreak == 10)
s3.reset(now: d(2026, 6, 8), calendar: cal)
check("longest survives reset", s3.currentStreak(now: d(2026, 6, 8), calendar: cal) == 0 && s3.longestStreak == 10)

print("Set start date (backdate):")
var bd = Streak(name: "D", startDay: day(2026, 5, 29))
bd.setStartDate(d(2026, 5, 22), now: d(2026, 5, 29), calendar: cal) // started a week ago
check("backdate a week ago makes it 7 days", bd.currentStreak(now: d(2026, 5, 29), calendar: cal) == 7)
check("backdate does NOT log a reset", bd.history.isEmpty)
check("backdate bumps longest", bd.longestStreak == 7)

print("Reset history:")
var h = Streak(name: "E", startDay: day(2026, 5, 1))
h.reset(now: d(2026, 5, 6), calendar: cal)              // break a 5-day streak
check("reset logs one record", h.history.count == 1)
check("record length is 5", h.lastReset?.length == 5)
check("record ended on reset day", h.lastReset?.endedOn == day(2026, 5, 6))
h.reset(now: d(2026, 5, 9), calendar: cal)              // new streak now 3 (anchor May 6)
check("second reset appends", h.history.count == 2)
check("history ordered oldest-first", h.history.first?.length == 5 && h.history.last?.length == 3)

print("Threshold tiers (StreakTier):")
check("0 days → cold (hollow)", StreakTier(streak: 0) == .cold && !StreakTier(streak: 0).isLit)
check("1 day → building (lit)", StreakTier(streak: 1) == .building && StreakTier(streak: 1).isLit)
check("6 → still building", StreakTier(streak: 6) == .building)
check("7 → week", StreakTier(streak: 7) == .week)
check("29 → still week", StreakTier(streak: 29) == .week)
check("30 → month", StreakTier(streak: 30) == .month)
check("100 → hundred", StreakTier(streak: 100) == .hundred)
check("364 → still hundred", StreakTier(streak: 364) == .hundred)
check("365 → year", StreakTier(streak: 365) == .year)

print("Undo reset (same-day misclick recovery):")
var u = Streak(name: "U", startDay: day(2026, 5, 1))
check("no undo available before any reset", !u.canUndoReset(now: d(2026, 5, 11), calendar: cal))
u.reset(now: d(2026, 5, 11), calendar: cal)             // misclick on a 10-day streak
check("after reset, undo IS available same day", u.canUndoReset(now: d(2026, 5, 11), calendar: cal))
check("reset dropped streak to 0", u.currentStreak(now: d(2026, 5, 11), calendar: cal) == 0)
check("reset logged a record", u.history.count == 1)
u.undoReset(now: d(2026, 5, 11), calendar: cal)
check("undo restores the 10-day streak", u.currentStreak(now: d(2026, 5, 11), calendar: cal) == 10)
check("undo removes the logged record", u.history.isEmpty)
check("undo is one-shot (not available after undo)", !u.canUndoReset(now: d(2026, 5, 11), calendar: cal))

var u2 = Streak(name: "U2", startDay: day(2026, 5, 1))
u2.reset(now: d(2026, 5, 6), calendar: cal)
check("undo not available the next day", !u2.canUndoReset(now: d(2026, 5, 7), calendar: cal))

var u3 = Streak(name: "U3", startDay: day(2026, 5, 1))
u3.reset(now: d(2026, 5, 9), calendar: cal)
check("undo present same day (pure)", u3.canUndoReset(now: d(2026, 5, 9), calendar: cal))
u3.clearStaleUndo(now: d(2026, 5, 10), calendar: cal)
check("clearStaleUndo drops a previous-day undo", u3.undo == nil)

// ---- StreakRoster ----------------------------------------------------------------------

func makeRoster(now: Date) -> StreakRoster {
    let suite = "check.\(UUID().uuidString)"
    let def = UserDefaults(suiteName: suite)!
    def.removePersistentDomain(forName: suite)
    return StreakRoster(defaults: def, calendar: cal, now: now)
}

print("StreakRoster (fresh install + persistence):")
let r1 = makeRoster(now: d(2026, 5, 29))
check("fresh install creates one streak", r1.streaks.count == 1)
check("fresh install auto-starts at 0", r1.activeCount == 0)
check("fresh install names it 'Streak'", r1.activeStreak?.name == "Streak")

let psuite = "check.\(UUID().uuidString)"
let pdef = UserDefaults(suiteName: psuite)!
pdef.removePersistentDomain(forName: psuite)
let first = StreakRoster(defaults: pdef, calendar: cal, now: d(2026, 5, 29))
let firstID = first.activeID
first.refresh(now: d(2026, 6, 2)) // 4 days
let second = StreakRoster(defaults: pdef, calendar: cal, now: d(2026, 6, 4))
check("roster persists across re-init (current)", second.activeCount == 6)
check("roster persists across re-init (longest)", second.activeStreak?.longestStreak == 6)
check("roster persists activeID", second.activeID == firstID)
pdef.removePersistentDomain(forName: psuite)

print("Multi-streak independence:")
let m = makeRoster(now: d(2026, 5, 1))
let gymID = m.activeID
m.rename(gymID, to: "Gym")
let readID = m.add(name: "Reading", now: d(2026, 5, 1))
m.setStartDate(gymID, d(2026, 4, 21), now: d(2026, 5, 1)) // Gym started 10 days ago
check("two streaks", m.streaks.count == 2)
check("add does not change the active streak", m.activeID == gymID)
check("Gym is 10 days", m.count(for: gymID) == 10)
check("Reading is 0 days", m.count(for: readID) == 0)
m.refresh(now: d(2026, 5, 6))
check("Gym advances independently to 15", m.count(for: gymID) == 15)
check("Reading advances independently to 5", m.count(for: readID) == 5)
m.reset(gymID, now: d(2026, 5, 6))                       // reset Gym only
check("reset Gym → 0", m.count(for: gymID) == 0)
check("Reading untouched by Gym's reset", m.count(for: readID) == 5)

print("Add / remove / active selection:")
let rr = makeRoster(now: d(2026, 5, 1))
let id1 = rr.activeID
let id2 = rr.add(name: "Two", now: d(2026, 5, 1))
let id3 = rr.add(name: "Three", now: d(2026, 5, 1))
check("three streaks", rr.streaks.count == 3)
check("active unchanged after adds", rr.activeID == id1)
rr.setActive(id2)
check("setActive switches the active streak", rr.activeID == id2)
rr.remove(id2, now: d(2026, 5, 1))                       // remove the active one
check("removing active reassigns to first remaining", rr.activeID == id1)
check("two streaks left", rr.streaks.count == 2)
rr.remove(id1, now: d(2026, 5, 1))
rr.remove(id3, now: d(2026, 5, 1))
check("deleting all leaves an empty roster", rr.isEmpty)
check("empty roster active count is 0", rr.activeCount == 0)

print("Rename:")
let rn = makeRoster(now: d(2026, 5, 1))
let rid = rn.activeID
rn.rename(rid, to: "  Pushups  ")
check("rename trims whitespace", rn.activeStreak?.name == "Pushups")
rn.rename(rid, to: "   ")
check("blank rename is ignored", rn.activeStreak?.name == "Pushups")

print("Migration from legacy single-streak keys:")
let msuite = "check.\(UUID().uuidString)"
let mdef = UserDefaults(suiteName: msuite)!
mdef.removePersistentDomain(forName: msuite)
// Seed legacy keys EXACTLY as the original StreakStore wrote them:
//  - startDay as a raw NSDate (defaults.set(date, ...))
//  - history via a bare JSONEncoder() (i.e. .deferredToDate)
mdef.set(day(2026, 5, 31), forKey: "streak.startDay")
mdef.set(true, forKey: "streak.everStarted")
mdef.set(27, forKey: "streak.longestStreak")
let legacyHistory = [ResetRecord(endedOn: day(2026, 5, 4), length: 2)]
mdef.set(try! JSONEncoder().encode(legacyHistory), forKey: "streak.history")
let migrated = StreakRoster(defaults: mdef, calendar: cal, now: d(2026, 6, 27))
check("migration yields exactly one streak", migrated.streaks.count == 1)
check("migrated streak is the active one", migrated.activeID == migrated.streaks.first?.id)
check("migrated anchor derives 27", migrated.activeCount == 27)
check("migrated longest preserved (27)", migrated.activeStreak?.longestStreak == 27)
check("migrated history preserved (len 2)",
      migrated.activeStreak?.history.count == 1 && migrated.activeStreak?.lastReset?.length == 2)
check("migrated history date intact (.deferredToDate decode)",
      migrated.activeStreak?.lastReset?.endedOn == day(2026, 5, 4))
check("migrated flag set", mdef.bool(forKey: "roster.migrated"))
let again = StreakRoster(defaults: mdef, calendar: cal, now: d(2026, 6, 27))
check("migration is idempotent (still one streak)", again.streaks.count == 1)
check("idempotent re-init still derives 27", again.activeCount == 27)
mdef.removePersistentDomain(forName: msuite)

print("Migration of a same-day undo snapshot (legacy undo.* keys):")
let usuite = "check.\(UUID().uuidString)"
let udef = UserDefaults(suiteName: usuite)!
udef.removePersistentDomain(forName: usuite)
udef.set(day(2026, 6, 27), forKey: "streak.startDay")     // reset today → anchor today
udef.set(true, forKey: "streak.everStarted")
udef.set(8, forKey: "streak.longestStreak")
udef.set(day(2026, 6, 19), forKey: "streak.undo.anchor")  // 8 days before "now"
udef.set(day(2026, 6, 27), forKey: "streak.undo.resetDay")
udef.set(true, forKey: "streak.undo.loggedRecord")
let mu = StreakRoster(defaults: udef, calendar: cal, now: d(2026, 6, 27))
check("migrated undo is available same day", mu.canUndoReset(mu.activeID, now: d(2026, 6, 27)))
mu.undoReset(mu.activeID, now: d(2026, 6, 27))
check("migrated undo restores the 8-day streak", mu.activeCount == 8)
udef.removePersistentDomain(forName: usuite)

print("Corrupt-blob recovery & deleted-all empty state:")
let csuite = "check.\(UUID().uuidString)"
let cdef = UserDefaults(suiteName: csuite)!
cdef.removePersistentDomain(forName: csuite)
cdef.set(day(2026, 5, 31), forKey: "streak.startDay")
cdef.set(true, forKey: "streak.everStarted")
cdef.set(27, forKey: "streak.longestStreak")
cdef.set(Data([0x00, 0x01, 0x02, 0xff]), forKey: "roster.v1")  // garbage blob
let recovered = StreakRoster(defaults: cdef, calendar: cal, now: d(2026, 6, 27))
check("corrupt blob recovers from legacy (not a fresh 0)", recovered.streaks.count == 1)
check("corrupt-blob recovery derives 27", recovered.activeCount == 27)
cdef.removePersistentDomain(forName: csuite)

let esuite = "check.\(UUID().uuidString)"
let edef = UserDefaults(suiteName: esuite)!
edef.removePersistentDomain(forName: esuite)
edef.set(day(2026, 5, 31), forKey: "streak.startDay")          // legacy keys present...
edef.set(true, forKey: "streak.everStarted")
let emptyBlob = #"{"schemaVersion":1,"streaks":[],"activeID":"00000000-0000-0000-0000-000000000000"}"#
edef.set(Data(emptyBlob.utf8), forKey: "roster.v1")            // ...but a VALID empty blob
let stayEmpty = StreakRoster(defaults: edef, calendar: cal, now: d(2026, 6, 27))
check("valid empty blob stays empty (legacy NOT resurrected)", stayEmpty.isEmpty)
check("loading a blob with legacy keys self-heals the migrated flag", edef.bool(forKey: "roster.migrated"))
edef.removePersistentDomain(forName: esuite)

// Once migrated, a corrupt blob must NOT resurrect now-stale legacy data (that would overwrite the
// user's current streaks). Recover to an empty roster instead.
let rsuite = "check.\(UUID().uuidString)"
let rdef = UserDefaults(suiteName: rsuite)!
rdef.removePersistentDomain(forName: rsuite)
rdef.set(day(2026, 5, 31), forKey: "streak.startDay")           // stale legacy single-streak
rdef.set(true, forKey: "streak.everStarted")
rdef.set(true, forKey: "roster.migrated")                       // already migrated
rdef.set(Data([0x00, 0xff]), forKey: "roster.v1")               // corrupt blob
let noResurrect = StreakRoster(defaults: rdef, calendar: cal, now: d(2026, 6, 27))
check("already-migrated + corrupt blob does NOT resurrect legacy", noResurrect.isEmpty)
rdef.removePersistentDomain(forName: rsuite)

print("Milestone progress:")
let m3 = Milestone(streak: 3)
check("at 3: next is 7", m3.next == 7)
check("at 3: previous is 0", m3.previous == 0)
check("at 3: 4 to go", m3.remaining == 4)
let m23 = Milestone(streak: 23)
check("at 23: next is 30", m23.next == 30)
check("at 23: previous is 7", m23.previous == 7)
check("at 23: segment fraction ≈ 0.696", abs(m23.fraction - (16.0/23.0)) < 0.0001)
check("at 23: caption '30 · 7 to go'", m23.caption == "30 · 7 to go")
let m30 = Milestone(streak: 30)
check("at 30: next jumps to 100", m30.next == 100)
check("at 30: fraction resets low", m30.fraction < 0.02)
let m400 = Milestone(streak: 400)
check("past 365: no next", m400.next == nil)
check("past 365: fraction is full", m400.fraction == 1)
check("past 365: no caption", m400.caption == nil)

if failures == 0 {
    print("\nAll checks passed ✅")
} else {
    print("\n\(failures) check(s) FAILED ❌")
    exit(1)
}
