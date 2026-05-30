import Foundation
import StreakKit

// A tiny runnable test harness. XCTest / the Testing framework aren't available under
// Command Line Tools, so we assert in plain code and exit non-zero on any failure.
// Run with:  swift run StreakKitCheck
//
// Model under test: **completed days since the anchor** — the anchor day reads 0 and each
// full calendar day since adds 1. Start and reset both land on 0 for "today".

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

func makeStore(now: Date) -> StreakStore {
    let suite = "check.\(UUID().uuidString)"
    let def = UserDefaults(suiteName: suite)!
    def.removePersistentDomain(forName: suite)
    return StreakStore(defaults: def, calendar: cal, now: now)
}

print("StreakStore:")
check("first launch auto-starts at 0",
      makeStore(now: d(2026, 5, 29)).currentStreak == 0)

let s1 = makeStore(now: d(2026, 5, 29))
s1.refresh(now: d(2026, 5, 31))
check("start then 2 days later reads 2", s1.currentStreak == 2)

let s2 = makeStore(now: d(2026, 5, 1))
s2.refresh(now: d(2026, 5, 6))
check("5-day streak", s2.currentStreak == 5)
s2.reset(now: d(2026, 5, 6))
check("reset reads 0 today", s2.currentStreak == 0)
s2.refresh(now: d(2026, 5, 7))
check("reset reads 1 tomorrow", s2.currentStreak == 1)

let s3 = makeStore(now: d(2026, 5, 29))
s3.refresh(now: d(2026, 6, 8))
check("10-day streak", s3.currentStreak == 10)
check("longest tracks 10", s3.longestStreak == 10)
s3.reset(now: d(2026, 6, 8))
check("longest survives reset", s3.currentStreak == 0 && s3.longestStreak == 10)

let psuite = "check.\(UUID().uuidString)"
let pdef = UserDefaults(suiteName: psuite)!
pdef.removePersistentDomain(forName: psuite)
let first = StreakStore(defaults: pdef, calendar: cal, now: d(2026, 5, 29))
first.refresh(now: d(2026, 6, 2)) // 4 days
let second = StreakStore(defaults: pdef, calendar: cal, now: d(2026, 6, 4))
check("state persists across re-init (current)", second.currentStreak == 6)
check("state persists across re-init (longest)", second.longestStreak == 6)
pdef.removePersistentDomain(forName: psuite)

print("Set start date (backdate):")
let bd = makeStore(now: d(2026, 5, 29))
bd.setStartDate(d(2026, 5, 22), now: d(2026, 5, 29)) // started a week ago
check("backdate a week ago makes it 7 days", bd.currentStreak == 7)
check("backdate does NOT log a reset", bd.history.isEmpty)
check("backdate bumps longest", bd.longestStreak == 7)

print("Reset history:")
let h = makeStore(now: d(2026, 5, 1))
h.refresh(now: d(2026, 5, 6))            // 5-day streak
h.reset(now: d(2026, 5, 6))              // break it
check("reset logs one record", h.history.count == 1)
check("record length is 5", h.lastReset?.length == 5)
check("record ended on reset day", h.lastReset?.endedOn == cal.startOfDay(for: d(2026, 5, 6)))
h.refresh(now: d(2026, 5, 9))            // new streak now 3 (anchor May 6)
h.reset(now: d(2026, 5, 9))
check("second reset appends", h.history.count == 2)
check("history ordered oldest-first", h.history.first?.length == 5 && h.history.last?.length == 3)

let hsuite = "check.\(UUID().uuidString)"
let hdef = UserDefaults(suiteName: hsuite)!
hdef.removePersistentDomain(forName: hsuite)
let hp1 = StreakStore(defaults: hdef, calendar: cal, now: d(2026, 5, 1))
hp1.refresh(now: d(2026, 5, 5))          // 4-day streak
hp1.reset(now: d(2026, 5, 5))            // logs a 4-day streak
let hp2 = StreakStore(defaults: hdef, calendar: cal, now: d(2026, 5, 7))
check("history persists across re-init", hp2.history.count == 1 && hp2.lastReset?.length == 4)
hdef.removePersistentDomain(forName: hsuite)

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
let u = makeStore(now: d(2026, 5, 1))
u.refresh(now: d(2026, 5, 11))           // 10-day streak
check("no undo available before any reset", !u.canUndoReset(now: d(2026, 5, 11)))
u.reset(now: d(2026, 5, 11))             // misclick
check("after reset, undo IS available same day", u.canUndoReset(now: d(2026, 5, 11)))
check("reset dropped streak to 0", u.currentStreak == 0)
check("reset logged a record", u.history.count == 1)
u.undoReset(now: d(2026, 5, 11))
check("undo restores the 10-day streak", u.currentStreak == 10)
check("undo removes the logged record", u.history.isEmpty)
check("undo is one-shot (not available after undo)", !u.canUndoReset(now: d(2026, 5, 11)))

let u2 = makeStore(now: d(2026, 5, 1))
u2.refresh(now: d(2026, 5, 6))
u2.reset(now: d(2026, 5, 6))
check("undo not available the next day", !u2.canUndoReset(now: d(2026, 5, 7)))

// Undo must survive a quit/relaunch within the same day.
let usuite = "check.\(UUID().uuidString)"
let udef = UserDefaults(suiteName: usuite)!
udef.removePersistentDomain(forName: usuite)
let up1 = StreakStore(defaults: udef, calendar: cal, now: d(2026, 5, 1))
up1.refresh(now: d(2026, 5, 9))          // 8-day streak
up1.reset(now: d(2026, 5, 9))
let up2 = StreakStore(defaults: udef, calendar: cal, now: d(2026, 5, 9, 18)) // relaunch, same day
check("undo survives relaunch same day", up2.canUndoReset(now: d(2026, 5, 9, 18)))
up2.undoReset(now: d(2026, 5, 9, 18))
check("undo after relaunch restores streak", up2.currentStreak == 8 && up2.history.isEmpty)
// Stale undo snapshot is dropped on next-day launch.
let up3 = StreakStore(defaults: udef, calendar: cal, now: d(2026, 5, 9))
up3.reset(now: d(2026, 5, 9))
let up4 = StreakStore(defaults: udef, calendar: cal, now: d(2026, 5, 10))
check("stale undo cleared on next-day launch", !up4.canUndoReset(now: d(2026, 5, 10)))
udef.removePersistentDomain(forName: usuite)

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
