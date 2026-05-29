import SwiftUI
import AppKit
import StreakKit

/// The dropdown shown when you click the menu bar number.
struct MenuContent: View {
    let store: StreakStore
    let loginItem: LoginItem

    var body: some View {
        if store.currentStreak == 0 {
            Text("🔥 0 days — back to 1 tomorrow")
        } else {
            Text("🔥 \(store.currentStreak) \(dayWord(store.currentStreak)) strong")
        }

        if store.longestStreak > 0 {
            Text("Longest: \(store.longestStreak) \(dayWord(store.longestStreak))")
        }
        if store.currentStreak >= 1, let started = store.startDay {
            Text("Started \(started.formatted(date: .abbreviated, time: .omitted))")
        }

        Divider()

        Button("Reset streak…") { confirmReset() }

        Toggle("Launch at login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))

        Divider()

        Button("Quit Streak Tracker") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func dayWord(_ n: Int) -> String { n == 1 ? "day" : "days" }

    /// Native confirm so an accidental click can't nuke a long streak.
    private func confirmReset() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reset your streak?"
        alert.informativeText =
            "Your streak of \(store.currentStreak) \(dayWord(store.currentStreak)) goes back to 0. "
            + "Tomorrow it starts again at 1."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.reset()
        }
    }
}
