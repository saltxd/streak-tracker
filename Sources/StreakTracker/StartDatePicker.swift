import AppKit
import StreakKit

/// Accessory view + controller for the "Set start date…" dialog: a graphical calendar
/// capped at today, plus a live label showing what the streak count will become. Held
/// alive by its caller for the lifetime of the modal (NSDatePicker's target is unretained).
@MainActor
final class StartDatePicker: NSObject {
    let view: NSView
    private let picker = NSDatePicker()
    private let previewLabel = NSTextField(labelWithString: "")
    private let calendar: Calendar
    private let now: Date

    /// The chosen day at start-of-day — the value to pass to `StreakStore.setStartDate`.
    var chosenDate: Date { calendar.startOfDay(for: picker.dateValue) }

    init(initialDate: Date, calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now

        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.maxDate = now                 // can't have started in the future
        picker.dateValue = min(initialDate, now)
        picker.sizeToFit()

        previewLabel.font = .systemFont(ofSize: 11)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.alignment = .center

        let stack = NSStackView(views: [picker, previewLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let w = max(220, picker.fittingSize.width + 16)
        stack.frame = NSRect(x: 0, y: 0, width: w, height: picker.fittingSize.height + 44)
        view = stack

        super.init()
        picker.target = self
        picker.action = #selector(pickerChanged)
        updatePreview()
    }

    @objc private func pickerChanged() { updatePreview() }

    private func updatePreview() {
        let value = DayMath.streakValue(startDay: chosenDate, now: now, calendar: calendar)
        switch value {
        case 0:  previewLabel.stringValue = "Starts today at 0 — counts 1 tomorrow."
        case 1:  previewLabel.stringValue = "That's a 1-day streak."
        default: previewLabel.stringValue = "That's a \(value)-day streak."
        }
    }
}
