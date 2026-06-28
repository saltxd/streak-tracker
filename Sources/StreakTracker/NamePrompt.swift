import AppKit

/// A modal text-input dialog for naming a streak (used by both "Add streak" and "Rename").
///
/// Kept on the dependable AppKit `NSAlert` path — SwiftUI sheets/alerts are unreliable from a
/// `.window` `MenuBarExtra` popover (it isn't part of a normal SwiftUI scene). The confirm
/// button is disabled while the trimmed name is empty or duplicates an existing streak, so
/// there's no error round-trip (the native macOS pattern).
///
/// The controller is its own `NSTextFieldDelegate` and is held on the stack for the modal's
/// duration — `NSTextField.delegate` is unretained, so a local that went out of scope would
/// silently stop validating.
@MainActor
final class NamePrompt: NSObject, NSTextFieldDelegate {
    private let field = NSTextField(string: "")
    private let existingLowercased: Set<String>
    private weak var confirmButton: NSButton?

    private init(initial: String, existingNames: [String]) {
        self.existingLowercased = Set(existingNames.map { $0.lowercased() })
        super.init()
        field.stringValue = initial
        field.placeholderString = "Streak name"
        field.delegate = self
        field.frame = NSRect(x: 0, y: 0, width: 250, height: 24)
    }

    /// Present the prompt modally and return the trimmed name, or nil if cancelled / blank.
    /// `existingNames` should exclude the streak being renamed so it can keep its own name.
    static func run(title: String,
                    message: String,
                    confirmTitle: String,
                    initial: String = "",
                    existingNames: [String]) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApplication.shared.deactivate() }

        let controller = NamePrompt(initial: initial, existingNames: existingNames)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = controller.field
        controller.confirmButton = alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        controller.validate()                                 // initial enabled state

        // The backing window only exists once the alert is built; make the field first
        // responder so the user can type immediately without an extra click.
        alert.window.initialFirstResponder = controller.field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = controller.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func controlTextDidChange(_ obj: Notification) { validate() }

    private func validate() {
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmButton?.isEnabled = !trimmed.isEmpty && !existingLowercased.contains(trimmed.lowercased())
    }
}
