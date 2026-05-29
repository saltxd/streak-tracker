# Streak Tracker

A dead-simple macOS menu bar streak counter — think the nofap-tracker number, sitting
quietly in your menu bar as `🔥 N`.

- **Counts up automatically** every new calendar day.
- **You slipped?** Click `Reset` — back to 0; it counts 1 again tomorrow.
- **Set start date** to backdate a streak you're already on.
- Tracks your **longest streak** and a **history** of past streaks.
- Flame strengthens at milestones (7 / 30 / 100 / 365 days).
- Menu-bar only, optional **Launch at login**.

## How the count works

It never stores a number it ticks up. It stores an *anchor day* and derives the count
from the clock, so it stays correct even if the app was closed for days, after reboots,
and across DST / timezone changes. The model is **completed days since the anchor**: the
anchor day reads `0`, and each full calendar day since adds `1`.

- **Start / Set start date:** anchor = that day → today reads `0`, then `1` at the next midnight.
- **Reset:** anchor = today → today reads `0` (logs the broken streak), `1` tomorrow.

Start and reset behave identically for "today" — both land on `0` — so the counter is
consistent however a streak begins.

## Build & run

Requires the Swift toolchain (Command Line Tools is enough — no full Xcode):

```sh
./build.sh              # builds + assembles StreakTracker.app
open StreakTracker.app  # look up at your menu bar 🔥
```

Install it for keeps:

```sh
cp -R StreakTracker.app /Applications/
open /Applications/StreakTracker.app
```

For **Launch at login** to stick, run it from `/Applications` and approve it in
System Settings › General › Login Items if macOS prompts.

## Develop

```sh
swift run StreakKitCheck   # runs the logic checks (works under Command Line Tools)
swift build                # debug build
```

> Tests are a plain runnable executable, not an XCTest target, because XCTest / the
> Testing framework aren't available with Command Line Tools alone.

## Layout

| Path | Purpose |
|---|---|
| `Sources/StreakKit/DayMath.swift` | Calendar-day arithmetic (pure) |
| `Sources/StreakKit/StreakStore.swift` | Persistence + derived streak values |
| `Sources/StreakKit/StreakTier.swift` | Milestone thresholds (7/30/100/365), pure |
| `Sources/StreakKit/ResetRecord.swift` | One past streak (date + length) |
| `Sources/StreakTracker/StreakTrackerApp.swift` | App entry, midnight timer, wake observer |
| `Sources/StreakTracker/MenuBarIcon.swift` | Composites the menu-bar flame + number |
| `Sources/StreakTracker/MenuContent.swift` | Dropdown menu, reset confirm, history |
| `Sources/StreakTracker/StartDatePicker.swift` | "Set start date" calendar dialog |
| `Sources/StreakTracker/LoginItem.swift` | Launch-at-login toggle (`SMAppService`) |
| `Sources/StreakKitCheck/main.swift` | Runnable logic checks (`swift run StreakKitCheck`) |
| `Tools/generate-icon.swift` | Regenerates the app icon artwork |
| `build.sh` | Builds + bundles the `.app` |
