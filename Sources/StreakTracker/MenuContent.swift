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

        if let last = store.lastReset {
            Divider()
            Text("Last reset \(agoPhrase(daysAgo(last.endedOn))) — broke a \(last.length)-day streak")
            if store.history.count > 1 {
                Menu("Streak history") {
                    ForEach(Array(store.history.suffix(10).enumerated()).reversed(), id: \.offset) { _, rec in
                        Text("\(rec.endedOn.formatted(date: .abbreviated, time: .omitted)): \(rec.length)-day streak")
                    }
                }
            }
        }

        Divider()

        Button("Set start date…") { chooseStartDate() }
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

    private func daysAgo(_ day: Date) -> Int { DayMath.dayCount(from: day, to: Date()) }

    private func agoPhrase(_ days: Int) -> String {
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// Graphical calendar dialog to backdate the streak's start. A correction, not a slip.
    private func chooseStartDate() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = StartDatePicker(initialDate: store.startDay ?? Date())
        let alert = NSAlert()
        alert.messageText = "Set your streak's start date"
        alert.informativeText = "Pick the day your streak began — that day counts as day 1."
        alert.accessoryView = picker.view
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.setStartDate(picker.chosenDate)
        }
    }

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
