import AppKit

/// Builds the menu-bar glyph: an SF Symbol flame followed by the streak number,
/// composited into one **template** `NSImage`. A template image is a pure alpha mask,
/// so the system tints it the same as the native Wi-Fi/battery icons and it adapts to
/// light/dark menu bars and the blue highlight when the menu is open.
///
/// `MenuBarExtra` won't reliably render an SF Symbol interpolated into `Text`, so we
/// draw the composite ourselves and hand it over as a single image.
enum MenuBarIcon {
    static func make(count: Int) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        let flame = NSImage(systemSymbolName: "flame", accessibilityDescription: "Streak")?
            .withSymbolConfiguration(symbolConfig)
        let flameSize = flame?.size ?? .zero

        let text = "\(count)" as NSString
        let font = NSFont.menuBarFont(ofSize: 0)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = text.size(withAttributes: textAttrs)

        let spacing: CGFloat = 3
        let height = ceil(max(flameSize.height, textSize.height))
        let width = ceil(flameSize.width + spacing + textSize.width)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if let flame {
            flame.draw(in: NSRect(x: 0, y: (height - flameSize.height) / 2,
                                  width: flameSize.width, height: flameSize.height))
        }
        text.draw(at: NSPoint(x: flameSize.width + spacing, y: (height - textSize.height) / 2),
                  withAttributes: textAttrs)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
