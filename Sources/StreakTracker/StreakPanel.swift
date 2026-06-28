import SwiftUI
import AppKit
import StreakKit

/// The custom `.window`-style popover shown when you click the menu bar flame.
///
/// Design: a "warm momentum" panel. The **active** streak is the hero — its number is the only
/// color in the panel (a warm amber gradient that's "earned": neutral at 0, glowing once lit),
/// with a milestone progress capsule. Below a divider, the *other* streaks appear as a quiet,
/// tappable list (tap one to make it active — the hero and the menu bar glyph both switch to
/// it). Then per-streak actions, add-streak, and the global toggles. With no streaks at all,
/// a designed empty state invites adding the first. The dialogs stay on the dependable AppKit
/// `NSAlert` path (SwiftUI sheets are unreliable from a `.window` MenuBarExtra popover).
struct StreakPanel: View {
    let roster: StreakRoster
    let loginItem: LoginItem

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            // Read activeStreak/streaks INSIDE body so a tap (activeID change) or a midnight
            // tick (counts change) re-registers the dependency and re-renders the hero.
            if let active = roster.activeStreak ?? roster.streaks.first {
                content(active)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(width: 300)
        .animation(.spring(duration: 0.35), value: roster.activeCount)
        .animation(.easeInOut(duration: 0.25), value: roster.activeID)
    }

    // MARK: Populated panel

    private func content(_ active: Streak) -> some View {
        let count = roster.count(for: active.id)
        let others = roster.streaks.filter { $0.id != active.id }
        return VStack(spacing: 0) {
            hero(active, count: count)
            if StreakTier(streak: count).isLit, Milestone(streak: count).next != nil {
                milestoneBar(count: count).padding(.top, 14)
            }

            Divider().padding(.vertical, 14)

            stats(active)
            if let last = active.lastReset {
                lastResetFootnote(last).padding(.top, 8)
            }

            Divider().padding(.vertical, 14)

            if !others.isEmpty {
                otherStreaks(others)
                Divider().padding(.vertical, 10)
            }

            actions(active, count: count)
        }
    }

    // MARK: Hero

    private func hero(_ active: Streak, count: Int) -> some View {
        let tier = StreakTier(streak: count)
        let isLit = tier.isLit
        return VStack(spacing: 4) {
            Image(systemName: isLit ? "flame.fill" : "flame")
                .font(.system(size: 26, weight: flameWeight(tier)))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isLit ? AnyShapeStyle(amber) : AnyShapeStyle(.tertiary))

            Text("\(count)")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isLit ? AnyShapeStyle(amber) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            // The streak's name is the caption; tap it to rename.
            Button(action: renameActive) {
                Text(active.name.uppercased())
                    .font(.caption.weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help("Rename streak")

            if count == 0 {
                Text("counts 1 tomorrow")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Milestone progress

    private func milestoneBar(count: Int) -> some View {
        let milestone = Milestone(streak: count)
        return VStack(spacing: 6) {
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

    private func stats(_ active: Streak) -> some View {
        HStack(alignment: .top) {
            statColumn("LONGEST", value: active.longestStreak > 0 ? "\(active.longestStreak) \(dayWord(active.longestStreak))" : "—")
            Spacer()
            if let started = active.startDay {
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

    // MARK: Other streaks (tap to activate)

    private func otherStreaks(_ others: [Streak]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OTHER STREAKS")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            // NSPopover has no auto-scroll; cap the height and scroll past a few streaks.
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(others) { streak in
                        StreakListRow(name: streak.name, count: roster.count(for: streak.id)) {
                            roster.setActive(streak.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)

            PanelRow(title: "Add streak", systemImage: "plus", tint: .accentColor) { addStreak() }
        }
    }

    // MARK: Actions (apply to the active streak)

    private func actions(_ active: Streak, count: Int) -> some View {
        VStack(spacing: 2) {
            if roster.canUndoReset(active.id) {
                PanelRow(title: "Undo reset", systemImage: "arrow.uturn.backward", tint: .accentColor) {
                    roster.undoReset(active.id)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            PanelRow(title: "Set start date…", systemImage: "calendar") { chooseStartDate() }

            if count > 0 {
                PanelRow(title: "Reset streak…", systemImage: "arrow.counterclockwise",
                         tint: .secondary, destructiveHover: true) { confirmReset() }
            }

            PanelRow(title: "Delete streak…", systemImage: "trash",
                     tint: .secondary, destructiveHover: true) { confirmDelete() }

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

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "flame")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text("No streaks yet")
                    .font(.headline)
                Text("Track your first habit — it counts 0 today and ticks to 1 tomorrow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Add your first streak") { addStreak() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Divider().padding(.vertical, 12)

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

    private func flameWeight(_ tier: StreakTier) -> Font.Weight {
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

    private func addStreak() {
        let name = NamePrompt.run(
            title: "Add a streak",
            message: "Name the habit you want to track. It counts 0 today and 1 tomorrow.",
            confirmTitle: "Add",
            initial: "New Streak",
            existingNames: roster.streaks.map { $0.name })
        guard let name else { return }
        let id = roster.add(name: name)
        // If the roster was empty (no valid active), focus the new streak.
        if roster.activeStreak == nil { roster.setActive(id) }
    }

    private func renameActive() {
        guard let active = roster.activeStreak ?? roster.streaks.first else { return }
        let others = roster.streaks.filter { $0.id != active.id }.map { $0.name }
        let name = NamePrompt.run(
            title: "Rename “\(active.name)”",
            message: "Choose a new name for this streak.",
            confirmTitle: "Rename",
            initial: active.name,
            existingNames: others)
        guard let name else { return }
        roster.rename(active.id, to: name)
    }

    /// Graphical calendar dialog to backdate the active streak's start. A correction, not a slip.
    private func chooseStartDate() {
        guard let active = roster.activeStreak ?? roster.streaks.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApplication.shared.deactivate() }
        let picker = StartDatePicker(initialDate: active.startDay ?? Date())
        let alert = NSAlert()
        alert.messageText = "Set “\(active.name)” start date"
        alert.informativeText = "Pick the day your streak began. That day counts as 0; each full day since adds 1."
        alert.accessoryView = picker.view
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            roster.setStartDate(active.id, picker.chosenDate)
        }
    }

    /// Native confirm so an accidental click can't nuke a long streak.
    private func confirmReset() {
        guard let active = roster.activeStreak ?? roster.streaks.first else { return }
        let count = roster.count(for: active.id)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApplication.shared.deactivate() }
        let alert = NSAlert()
        alert.messageText = "Reset “\(active.name)”?"
        alert.informativeText =
            "Your streak of \(count) \(dayWord(count)) goes back to 0. Tomorrow it starts again at 1."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        // Cancel is the default (rightmost / Return) so a stray Return doesn't reset.
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn {
            roster.reset(active.id)
        }
    }

    /// Native confirm for deletion — destroys the streak's history irreversibly.
    private func confirmDelete() {
        guard let active = roster.activeStreak ?? roster.streaks.first else { return }
        let count = roster.count(for: active.id)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApplication.shared.deactivate() }
        let alert = NSAlert()
        alert.messageText = "Delete “\(active.name)”?"
        alert.informativeText =
            "Its \(count)-\(dayWord(count)) streak and history will be permanently removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn {
            roster.remove(active.id)
        }
    }
}

/// A full-width tappable row with a native menu-style hover highlight — the thing that makes a
/// `.window` popover (which has no free menu chrome) still feel like a menu.
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

/// A tappable row for a non-active streak: small flame, name, current count, with the same
/// menu-style hover highlight as `PanelRow`. Tapping it makes the streak active.
private struct StreakListRow: View {
    let name: String
    let count: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let lit = StreakTier(streak: count).isLit
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: lit ? "flame.fill" : "flame")
                    .frame(width: 16)
                    .foregroundStyle(lit ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.07) : Color.clear)
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
