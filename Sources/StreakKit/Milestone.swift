import Foundation

/// Progress toward the next streak milestone (7 / 30 / 100 / 365 days).
///
/// Progress is measured *within the current segment* — from the previously-passed
/// milestone to the next one — so the bar is always meaningfully full instead of
/// crawling against an ever-growing absolute. Pure (no UI) so it's unit-checkable.
public struct Milestone: Equatable, Sendable {
    /// Ordered milestone thresholds. Mirrors `StreakTier`'s boundaries.
    public static let thresholds = [7, 30, 100, 365]

    /// The milestone being worked toward, or nil once past the last one (365+).
    public let next: Int?
    /// The most recently passed milestone (0 if none yet).
    public let previous: Int
    /// Days remaining to `next` (0 when there is no next).
    public let remaining: Int
    /// Segment fill in 0...1. Always 1 once past the final milestone.
    public let fraction: Double

    public init(streak: Int) {
        let next = Milestone.thresholds.first { $0 > streak }
        self.next = next
        let prev = Milestone.thresholds.last { $0 <= streak } ?? 0
        self.previous = prev
        if let next {
            remaining = next - streak
            let span = Double(next - prev)
            fraction = span > 0 ? min(1, max(0, Double(streak - prev) / span)) : 0
        } else {
            remaining = 0
            fraction = 1
        }
    }

    /// A short, single-line caption like "30 · 18 to go", or nil when there's nothing to chase.
    public var caption: String? {
        guard let next else { return nil }
        return "\(next) · \(remaining) to go"
    }
}
