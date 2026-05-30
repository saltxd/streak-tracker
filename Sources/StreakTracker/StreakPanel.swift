import SwiftUI
import AppKit
import StreakKit

/// The custom `.window`-style popover shown when you click the menu bar flame.
///
/// Design (from the UX team's synthesis): a "warm momentum" panel — the streak number
/// is the hero, carrying the *only* color in the panel (a warm amber gradient that is
/// "earned": neutral at 0, glowing once lit). A thin capsule shows progress *within* the
/// current milestone segment, so it's always meaningfully full. Everything else is quiet,
/// native, semantic-colored chrome. Reset is de-emphasized; Undo appears only as a gated
/// row right after a same-day reset. The two dialogs stay on the dependable AppKit
/// `NSAlert` path (SwiftUI sheets/confirmationDialogs are unreliable from a `.window`
/// MenuBarExtra popover).
struct StreakPanel: View {
    let store: StreakStore
    let loginItem: LoginItem

    @Environment(\.colorScheme) private var scheme

    private var tier: StreakTier { StreakTier(streak: store.currentStreak) }
    private var milestone: Milestone { Milestone(streak: store.currentStreak) }
    private var isLit: Bool { tier.isLit }

    var body: some View {
        VStack(spacing: 0) {
            hero
            if isLit, milestone.next != nil {
                milestoneBar
                    .padding(.top, 14)
            }

            Divider().padding(.vertical, 14)

            stats
            if let last = store.lastReset {
                lastResetFootnote(last)
                    .padding(.top, 8)
            }

            Divider().padding(.vertical, 14)

            actions
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(width: 300)
        .animation(.spring(duration: 0.35), value: store.currentStreak)
        .animation(.easeInOut(duration: 0.25), value: store.canUndoReset())
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 4) {
            Image(systemName: isLit ? "flame.fill" : "flame")
                .font(.system(size: 26, weight: flameWeight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isLit ? AnyShapeStyle(amber) : AnyShapeStyle(.tertiary))

            Text("\(store.currentStreak)")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isLit ? AnyShapeStyle(amber) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            Text(heroCaption)
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }

    private var heroCaption: String {
        if store.currentStreak == 0 { return "counts 1 tomorrow" }
        return store.currentStreak == 1 ? "day streak" : "days streak"
    }

    // MARK: Milestone progress

    private var milestoneBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(amber)
                        .frame(width: max(4, geo.size.width * milestone.fraction))
                }
            }
            .frame(height: 5)

            if let caption = milestone.caption {
                Text(caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: Stats

    private var stats: some View {
        HStack(alignment: .top) {
            statColumn("LONGEST", value: store.longestStreak > 0 ? "\(store.longestStreak) \(dayWord(store.longestStreak))" : "—")
            Spacer()
            if let started = store.startDay {
                statColumn("STARTED", value: started.formatted(.dateTime.month(.abbreviated).day().year()), trailing: true)
            }
        }
    }

    private func statColumn(_ label: String, value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func lastResetFootnote(_ last: ResetRecord) -> some View {
        Text("Last reset \(agoPhrase(daysAgo(last.endedOn))) · broke a \(last.length)-\(dayWord(last.length)) streak")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 2) {
            if store.canUndoReset() {
                PanelRow(title: "Undo reset", systemImage: "arrow.uturn.backward", tint: .accentColor) {
                    store.undoReset()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            PanelRow(title: "Set start date…", systemImage: "calendar") { chooseStartDate() }

            if store.currentStreak > 0 {
                PanelRow(title: "Reset streak…", systemImage: "arrow.counterclockwise",
                         tint: .secondary, destructiveHover: true) { confirmReset() }
            }

            Toggle(isOn: Binding(get: { loginItem.isEnabled },
                                 set: { loginItem.setEnabled($0) })) {
                Label("Launch at login", systemImage: "power")
                    .labelStyle(PanelLabelStyle())
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider().padding(.vertical, 6)

            PanelRow(title: "Quit Streak Tracker", systemImage: "power",
                     showIcon: false, trailing: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: Styling helpers

    private var amber: LinearGradient {
        let stops: [Color] = scheme == .dark
            ? [Color(red: 1.00, green: 0.80, blue: 0.42), Color(red: 1.00, green: 0.52, blue: 0.22)]
            : [Color(red: 1.00, green: 0.70, blue: 0.24), Color(red: 0.96, green: 0.38, blue: 0.13)]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    private var flameWeight: Font.Weight {
        switch tier {
        case .cold, .building: return .regular
        case .week: return .semibold
        case .month: return .bold
        case .hundred: return .heavy
        case .year: return .black
        }
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

    // MARK: Dialogs (kept on the dependable AppKit NSAlert path)

    /// Graphical calendar dialog to backdate the streak's start. A correction, not a slip.
    private func chooseStartDate() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = StartDatePicker(initialDate: store.startDay ?? Date())
        let alert = NSAlert()
        alert.messageText = "Set your streak's start date"
        alert.informativeText = "Pick the day your streak began. That day counts as 0; each full day since adds 1."
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
        // Cancel is the default (rightmost / Return) so a stray Return doesn't reset.
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn {
            store.reset()
        }
    }
}

/// A full-width tappable row with a native menu-style hover highlight — the thing that
/// makes a `.window` popover (which has no free menu chrome) still feel like a menu.
private struct PanelRow: View {
    let title: String
    var systemImage: String = ""
    var tint: Color = .primary
    var destructiveHover: Bool = false
    var showIcon: Bool = true
    var trailing: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if showIcon {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                        .foregroundStyle(tint == .primary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                }
                Text(title)
                    .foregroundStyle(destructiveHover && hovering ? AnyShapeStyle(.red) : AnyShapeStyle(tint))
                Spacer()
                if let trailing {
                    Text(trailing).foregroundStyle(.tertiary)
                }
            }
            .font(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? (destructiveHover ? Color.red.opacity(0.12) : Color.primary.opacity(0.07))
                                   : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Label style that matches PanelRow spacing for the Launch-at-login toggle.
private struct PanelLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.frame(width: 16).foregroundStyle(.secondary)
            configuration.title
        }
    }
}
