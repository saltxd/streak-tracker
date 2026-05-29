# Streak Tracker

A dead-simple macOS menu bar streak counter — think the nofap-tracker number, sitting
quietly in your menu bar as `🔥 N`.

- **Counts up automatically** every new calendar day.
- **You slipped?** Click `Reset` — back to 0, and it starts again at 1 tomorrow.
- Tracks your **longest streak** ever.
- Menu-bar only (no dock icon), optional **Launch at login**.

## How the count works

It never stores a number it ticks up. It stores an *anchor day* and derives the count
from the clock, so it stays correct even if the app was closed for days, after reboots,
and across DST / timezone changes. The anchor day reads as **1**.

- **Start:** anchor = today → today reads `1`.
- **Reset:** anchor = tomorrow → today reads `0`, tomorrow reads `1`.

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
| `Sources/StreakTracker/StreakTrackerApp.swift` | App entry, midnight timer, wake observer |
| `Sources/StreakTracker/MenuContent.swift` | The dropdown menu + reset confirm |
| `Sources/StreakTracker/LoginItem.swift` | Launch-at-login toggle (`SMAppService`) |
| `Sources/StreakKitCheck/main.swift` | Runnable logic checks (`swift run StreakKitCheck`) |
| `build.sh` | Builds + bundles the `.app` |
