import SwiftUI
import AppKit
import StreakKit

@main
struct StreakTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: delegate.store, loginItem: delegate.loginItem)
        } label: {
            StreakLabel(store: delegate.store)
        }
    }
}

/// The number in the menu bar. Uses an SF Symbol flame (a *template* glyph) rather
/// than the 🔥 emoji, so it renders monochrome and adapts to light/dark + highlight
/// exactly like the native Wi-Fi/battery icons. A dedicated view so Observation
/// reliably re-renders it on every change (midnight, reset, wake-from-sleep).
private struct StreakLabel: View {
    let store: StreakStore
    var body: some View {
        Image(nsImage: MenuBarIcon.make(count: store.currentStreak))
            .renderingMode(.template)
    }
}

/// Owns app-lifetime concerns: the single store, the midnight refresh timer, and the
/// wake-from-sleep observer. Keeping these here (not in the SwiftUI graph) makes the
/// timing rock-solid regardless of whether the menu is ever opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = StreakStore()
    let loginItem = LoginItem()
    private var midnightTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.refresh()
        scheduleMidnightRefresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func systemDidWake() {
        store.refresh()
        scheduleMidnightRefresh()
    }

    @objc private func midnightFired() {
        store.refresh()
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
