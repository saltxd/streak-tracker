import SwiftUI
import AppKit
import StreakKit

@main
struct StreakTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StreakPanel(roster: delegate.roster, loginItem: delegate.loginItem)
        } label: {
            StreakLabel(roster: delegate.roster)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The number in the menu bar — the **active** streak's flame + count. Uses an SF Symbol flame
/// (a *template* glyph) rather than the 🔥 emoji, so it renders monochrome and adapts to
/// light/dark + highlight exactly like the native Wi-Fi/battery icons. A dedicated view that
/// reads the observed `activeCount` *inside* its body, so Observation reliably re-renders it on
/// every change: midnight rollover, reset, wake-from-sleep, and switching the active streak.
private struct StreakLabel: View {
    let roster: StreakRoster
    var body: some View {
        Image(nsImage: MenuBarIcon.make(count: roster.activeCount))
            .renderingMode(.template)
    }
}

/// Owns app-lifetime concerns: the single roster, the midnight refresh timer, and the
/// wake-from-sleep observer. Keeping these here (not in the SwiftUI graph) makes the timing
/// rock-solid regardless of whether the menu is ever opened. `refresh()` advances *every*
/// streak (each derives its own count), so a later switch never shows a stale number.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let roster = StreakRoster()
    let loginItem = LoginItem()
    private var midnightTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        roster.refresh()
        scheduleMidnightRefresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func systemDidWake() {
        roster.refresh()
        scheduleMidnightRefresh()
    }

    @objc private func midnightFired() {
        roster.refresh()
        scheduleMidnightRefresh()
    }

    /// Fire once at the next local midnight, refresh, then reschedule for the day after.
    /// Target/selector (not a closure) keeps this free of Sendable-capture warnings.
    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let timer = Timer(
            fireAt: DayMath.nextMidnight(after: Date()),
            interval: 0, target: self, selector: #selector(midnightFired),
            userInfo: nil, repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
