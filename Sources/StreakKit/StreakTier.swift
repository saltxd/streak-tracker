import Foundation

/// How "strong" the flame looks, by streak length. Classic milestones: 7 / 30 / 100 / 365.
/// Pure (no AppKit) so the threshold decision is testable; the app maps each tier to an
/// SF Symbol weight when drawing the menu-bar glyph.
public enum StreakTier: Sendable, Equatable {
    case cold       // 0 — just reset / not lit
    case building   // 1–6
    case week       // 7–29
    case month      // 30–99
    case hundred    // 100–364
    case year       // 365+

    public init(streak: Int) {
        switch streak {
        case ..<1:      self = .cold
        case 1..<7:     self = .building
        case 7..<30:    self = .week
        case 30..<100:  self = .month
        case 100..<365: self = .hundred
        default:        self = .year
        }
    }

    /// Whether the flame is drawn filled (lit) or hollow (cold).
    public var isLit: Bool { self != .cold }
}
