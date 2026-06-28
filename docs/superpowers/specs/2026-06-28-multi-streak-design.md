# Multi-streak tracking — design

- **Date:** 2026-06-28
- **Status:** Approved, implementing
- **Author:** brainstormed with the user; best practices verified via parallel research (see References)

## Summary

Streak Tracker currently tracks exactly **one** streak: one `StreakStore`, one set of
`streak.*` `UserDefaults` keys, one menu-bar glyph. The user wants to track **a few named
streaks** (add/remove freely) **without disturbing their existing 27-day streak**.

We refactor the single-streak model into a small collection model and present multiple
streaks through the existing, well-liked UI with minimal new chrome. The menu bar keeps
showing exactly **one** streak (best practice for menu-bar real estate); the popover gains
a compact list of the others.

## Decisions (from brainstorming)

1. **Scope:** a small, arbitrary number of **named** streaks; user can add and delete.
2. **Menu bar:** shows exactly **one** "active" streak (flame + number), exactly as today.
   Never multiple glyphs / no count badge. Switchable from the panel.
3. **Panel:** keep the signature **hero** (big number, flame, milestone bar, stats) for the
   active streak, plus a **compact list** of the others. One concept: **active = hero =
   menu bar = action target.** Tapping a list row makes that streak active.
4. **Migrated streak's name:** defaults to `"Streak"` (editable inline). New streaks default
   to `"New Streak"`.

## Current architecture (for reference)

- `StreakKit` (pure, no UI): `StreakStore` (`@Observable`, owns state + `UserDefaults`
  persistence), `DayMath`, `Milestone`, `StreakTier`, `ResetRecord`.
- `StreakTracker` (UI): `StreakTrackerApp` (one `MenuBarExtra`, `.window` style),
  `StreakPanel` (popover), `MenuBarIcon` (template-`NSImage` flame+number), `StartDatePicker`
  (AppKit accessory for the date dialog), `LoginItem`.
- `StreakKitCheck` (plain executable test harness; XCTest is unavailable under CLT).

The count is **derived from the clock** — an anchor day is stored and the displayed value is
`completed days since anchor`, so it survives reboots/DST. This stays.

## Real persisted data (the migration target — verified on this machine)

```
streak.everStarted   = 1
streak.startDay      = 2026-05-31 06:00:00 +0000   (raw NSDate; == 2026-05-31 local start-of-day)
streak.longestStreak = 27
streak.history       = <JSON data>                 (one ResetRecord: a broken 2-day streak)
```

At "now" this derives to 27 — matching the screenshot. **Migration must reproduce this exactly.**

> **Date-encoding hazard (highest-risk bug):** `StreakStore` writes `startDay` and the undo
> snapshot dates as **raw `NSDate`** via `defaults.set(date, …)`, but writes `history` with a
> bare `JSONEncoder()` (i.e. `.deferredToDate`). The migration reader **must** decode each in
> its original format. A uniform date strategy would silently corrupt the anchor or fail to
> decode history.

## Data model (`StreakKit`)

```swift
public struct Streak: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var startDay: Date?
    public var longestStreak: Int
    public var history: [ResetRecord]
    public var undo: UndoSnapshot?          // per-streak same-day undo
    // currentStreak is DERIVED, never stored.
    // Decode-tolerant: every field optional-with-default / custom init(from:) so an older
    // blob (downgrade → re-upgrade) still decodes instead of throwing keyNotFound.
}

public struct UndoSnapshot: Codable, Equatable, Sendable {
    public let anchor: Date?                // previous startDay
    public let resetDay: Date               // calendar day the reset happened
    public let loggedRecord: Bool           // whether the reset appended history
}

@Observable public final class StreakRoster {
    public private(set) var streaks: [Streak]
    public private(set) var activeID: UUID
    public var activeStreak: Streak? { streaks.first { $0.id == activeID } }
    // activeCount derived: DayMath.streakValue(startDay: activeStreak?.startDay, now:)

    // collection ops (all on MainActor, persist after each mutation):
    func setActive(_ id: UUID); func add(name:) -> UUID; func remove(_ id:); func rename(_ id:, to:)
    // per-streak ops (delegate to the streak's pure logic, then persist):
    func reset(_ id:); func setStartDate(_ id:, _ date:); func undoReset(_ id:); func canUndoReset(_ id:) -> Bool
    func refreshAll(now:)                    // recompute every streak's derived count + bump each longest
}
```

- `Streak` is a **pure value type**; only `StreakRoster` is `@Observable`. Value-type elements
  are what make in-array mutations propagate to the label and hero (an array of `@Observable`
  classes would go stale). `activeStreak`/`activeCount` are **computed over stored props**, so
  Observation tracks them automatically (label invalidates on both midnight count changes and
  `activeID` switches).
- The per-streak reset/undo/backdate/start logic moves verbatim (in behavior) from `StreakStore`
  onto `Streak`, but **pure** (takes `now`, no `UserDefaults`) — even more testable than today.
- `DayMath`, `Milestone`, `StreakTier`, `ResetRecord` are unchanged.

## Persistence & migration

- **One JSON blob** under a versioned key `roster.v1`, plus `activeID`. A single atomic
  `set()` per mutation (UserDefaults has no multi-key transaction). The roster Codable embeds
  `schemaVersion: Int` **inside** the model (the key name alone is invisible to the decoder).
- **Shared coder:** one lazily-created `JSONEncoder`/`JSONDecoder` pair with one explicit date
  strategy (`.iso8601`) for the **new** blob, so encode/decode can never diverge. (This is
  separate from the legacy reader, which must use the legacy formats.)
- **Migration (in `StreakRoster.init`, before first label render, `@ObservationIgnored`
  defaults):**
  1. If `roster.v1` exists → decode with `do/catch`. On success, load. **On decode error →
     fall through to legacy recovery** (never `try?`→nil, which would masquerade as a fresh
     install and reset the menu bar to 0).
  2. Else if legacy `streak.*` keys exist (or `everStarted == true`) → build **one** `Streak`:
     fresh UUID, name `"Streak"`, `startDay`/undo dates read as **raw `NSDate`**, `history`
     decoded with a **default-strategy** `JSONDecoder`, `longestStreak` from the int key, undo
     snapshot from `streak.undo.*`. Set it as the only streak and as `activeID`. **Write the
     blob, then set the `migrated` flag LAST** (crash-safe; guard on `roster.v1 absent &&
     migrated == false` so a mid-migration crash retries rather than skips/duplicates).
  3. Else → genuine fresh install: one fresh streak anchored today, active.
- **Legacy keys are NOT deleted** this release — kept read-only as a rollback/recovery path
  (sideloaded open-source app; users can run old binaries). Comment marks them intentional.
- **Downgrade → re-upgrade policy (documented):** *first upgrade wins.* Once `migrated == true`,
  a newer edit an old binary made to `streak.*` is not re-imported. Acceptable for a one-way
  single→multi move.

## Menu bar

- Unchanged in spirit: `MenuBarIcon.make(count:)` reused verbatim (template `NSImage`,
  resolution-independent drawing-handler, `StreakTier`-driven `flame.fill`/`flame` + weight).
- `StreakLabel` reads `roster.activeCount` **inside `body`** and builds exactly one glyph for
  the active streak. Switching active recomposites the glyph; midnight/wake advance all streaks.
- **Refinement:** render the number with **monospaced-digit** figures (apply the monospaced
  feature to `NSFont.menuBarFont`) so the `.variableLength` item doesn't jitter as the count
  ticks `9→10→100` or when switching streaks. A cold/just-added active streak shows hollow
  `flame` + `0`, still `isTemplate = true` (no color).

## Panel UI

- **Hero (active streak):** existing styling. Reads `roster.activeStreak` fields **directly in
  `body`** (not captured into a `let` above `body`, or row taps won't update it). The streak's
  **name** shows as the caption; tap to rename.
- **List of the other streaks:** `ForEach(streaks)` keyed by `id`, **excluding the active one**
  (it's already the hero). Each row: small flame + name (tail-truncated) + current number. Tap
  → `setActive` (a `Button` action, off the body path). The active streak is the hero, so the
  list never shows an un-highlighted duplicate.
- **Scroll:** wrap rows in a `List`/`ScrollView` with a fixed `maxHeight` (hero + ~4–6 rows,
  then scroll). Popover stays `.frame(width: 300)`; never grows unbounded.
- **Empty state:** if there are zero streaks (fresh install with no legacy keys, or the user
  deleted the last one), show a one-line explanation + a single **"Add your first streak"**
  button — not an absent hero.
- **Actions (apply to the active streak):** `Set start date…`, `Reset…` (gated), `Undo reset`
  (gated, same-day), `Delete streak…` (gated; **allowed even for the last streak → routes to
  the empty state**), `+ Add streak`. `Launch at login` + `Quit` stay global.

### Dialogs (AppKit `NSAlert`, kept for reliability)

- Confirmed correct: `MenuBarExtra(.window)` is an AppKit popover outside the SwiftUI scene
  hierarchy, so sheets/`confirmationDialog` fail silently. Use standalone `runModal()`.
- **`promptForName(title:informative:initial:existingNames:) -> String?`** — one reusable
  helper for **add and rename**: `NSApp.activate`; `NSAlert` + `NSTextField` accessory
  (~250pt, placeholder, initial = current name for rename); capture the OK button; a
  **retained** `NSTextFieldDelegate` (held on a `@MainActor` controller, like `StartDatePicker`)
  disables OK on empty/whitespace **and case-insensitive duplicate** (rename excludes itself);
  `alert.window.initialFirstResponder = textField` **before** `runModal()`; read trimmed value
  after `.alertFirstButtonReturn`; `NSApplication.shared.deactivate()` after.
- **Delete:** reuse `confirmReset()`'s key-equivalent demotion verbatim (`.warning`, add
  `Delete` then `Cancel`, `buttons.first.keyEquivalent=""`, `buttons.last.keyEquivalent="\r"`,
  Cancel is the bold default). Informative text names the streak and its length.
- Add `NSApplication.shared.deactivate()` after `runModal()` to the **existing**
  `chooseStartDate()` and `confirmReset()` too (they activate but never deactivate).

## App lifecycle (`AppDelegate`)

- Keep the `Timer(fireAt:)` on `RunLoop.main` `.common` + `NSWorkspace.didWakeNotification`
  observer outside the SwiftUI graph. `midnightFired`/`systemDidWake` call
  `roster.refreshAll(now:)` so **every** streak advances (only the active one drives the label,
  but a later switch must not show a stale count).

## Verification strategy

- **Logic (local, works):** extend `StreakKitCheck` and run `swift run StreakKitCheck`. CLT can
  build `StreakKit` + the harness.
- **SwiftUI app compile (CI):** the local toolchain (CLT only, Swift 6.4 / macOS 27 SDK) lacks
  the `SwiftUIMacros` plugin, so the `StreakTracker` app target **cannot compile locally**. Add
  a CI build-check job on `macos-15` (full Xcode) that runs `swift build` + `StreakKitCheck` +
  `build.sh` to prove the SwiftUI compiles and the bundle assembles.
- **Visual ("looking legit"):** can't be screenshotted headlessly. The user runs the CI-built
  `.app` (or builds locally if Xcode is installed). Report this honestly.

## Testing plan (`StreakKitCheck`)

Keep all existing assertions (now against the pure `Streak`): day math, reset → 0/1, longest
survives reset, backdate (no history log), reset history ordering, tiers, same-day undo
(including survives relaunch / stale next-day), milestones. **Add:**

- **Migration:** seed an in-memory `UserDefaults(suiteName:)` with **both legacy Date formats**
  (raw `NSDate` `startDay`/undo + `.deferredToDate` `history` JSON, `longest`, `everStarted`),
  run migration → assert one active streak with the right derived count, longest, history,
  and undo snapshot; `migrated` flag set; idempotent on re-init (no duplicate).
- **Decode-error recovery:** a corrupt `roster.v1` with legacy keys present → recovers from
  legacy, not an empty roster.
- **Multi-streak independence:** two streaks with different anchors compute independently;
  reset/undo on one doesn't touch the other.
- **Add/remove:** add doesn't change `activeID`; deleting the active reassigns it; deleting the
  last yields an empty roster (empty-state path).
- **Rename:** trims; empty/duplicate rejected at the model boundary.
- **Persistence:** roster + `activeID` round-trip across re-init.

## Out of scope (YAGNI)

Per-streak notifications/reminders, custom colors/icons per streak, reordering, iCloud sync,
multiple menu-bar glyphs, a settings window.

## References

Apple HIG (menu bar, alerts), `MenuBarExtra`/Observation docs, and the SwiftUI `MenuBarExtra`
re-render + sheet-from-popover feedback reports; AppKit `NSAlert`/`initialFirstResponder`;
`JSONEncoder.dateEncodingStrategy`; habit-tracker UX (Habitify, Streaks). Full citation list in
the best-practice research output for this change.
