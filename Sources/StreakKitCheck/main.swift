import Foundation
import StreakKit

// A tiny runnable test harness. XCTest / the Testing framework aren't available under
// Command Line Tools, so we assert in plain code and exit non-zero on any failure.
// Run with:  swift run StreakKitCheck

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

print("DayMath:")
check("anchor day reads 1",
      DayMath.streakValue(startDay: cal.startOfDay(for: d(2026, 5, 29)), now: d(2026, 5, 29), calendar: cal) == 1)
check("next day reads 2",
      DayMath.streakValue(startDay: cal.startOfDay(for: d(2026, 5, 29)), now: d(2026, 5, 30), calendar: cal) == 2)
let resetAnchor = DayMath.tomorrow(d(2026, 5, 29), calendar: cal)
check("reset anchor reads 0 today",
      DayMath.streakValue(startDay: resetAnchor, now: d(2026, 5, 29), calendar: cal) == 0)
check("reset anchor reads 1 tomorrow",
      DayMath.streakValue(startDay: resetAnchor, now: d(2026, 5, 30), calendar: cal) == 1)
check("clock set backwards floors at 0",
      DayMath.streakValue(startDay: cal.startOfDay(for: d(2026, 5, 29)), now: d(2026, 5, 25), calendar: cal) == 0)
check("DST spring-forward counts 3 calendar days",
      DayMath.streakValue(startDay: cal.startOfDay(for: d(2026, 3, 7)), now: d(2026, 3, 9), calendar: cal) == 3)
check("nil start is 0",
      DayMath.streakValue(startDay: nil, now: d(2026, 5, 29), calendar: cal) == 0)
check("count across month boundary",
      DayMath.streakValue(startDay: cal.startOfDay(for: d(2026, 5, 29)), now: d(2026, 6, 4), calendar: cal) == 7)

func makeStore(now: Date) -> StreakStore {
    let suite = "check.\(UUID().uuidString)"
    let def = UserDefaults(suiteName: suite)!
    def.removePersistentDomain(forName: suite)
    return StreakStore(defaults: def, calendar: cal, now: now)
}

print("StreakStore:")
check("first launch auto-starts at 1",
      makeStore(now: d(2026, 5, 29)).currentStreak == 1)

let s1 = makeStore(now: d(2026, 5, 29))
s1.refresh(now: d(2026, 5, 31))
check("start then 2 days later reads 3", s1.currentStreak == 3)

let s2 = makeStore(now: d(2026, 5, 29))
s2.reset(now: d(2026, 5, 29))
check("reset reads 0 today", s2.currentStreak == 0)
s2.refresh(now: d(2026, 5, 30))
check("reset reads 1 tomorrow", s2.currentStreak == 1)

let s3 = makeStore(now: d(2026, 5, 29))
s3.refresh(now: d(2026, 6, 7))
check("10-day streak", s3.currentStreak == 10)
check("longest tracks 10", s3.longestStreak == 10)
s3.reset(now: d(2026, 6, 7))
check("longest survives reset", s3.currentStreak == 0 && s3.longestStreak == 10)

let suite = "check.\(UUID().uuidString)"
let def = UserDefaults(suiteName: suite)!
def.removePersistentDomain(forName: suite)
let first = StreakStore(defaults: def, calendar: cal, now: d(2026, 5, 29))
first.refresh(now: d(2026, 6, 2))
let second = StreakStore(defaults: def, calendar: cal, now: d(2026, 6, 4))
check("state persists across re-init (current)", second.currentStreak == 7)
check("state persists across re-init (longest)", second.longestStreak == 7)
def.removePersistentDomain(forName: suite)

if failures == 0 {
    print("\nAll checks passed ✅")
} else {
    print("\n\(failures) check(s) FAILED ❌")
    exit(1)
}
