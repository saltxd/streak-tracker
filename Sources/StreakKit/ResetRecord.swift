import Foundation

/// One past streak that ended at a reset: the day it ended and how many days it ran.
/// Persisted (JSON in UserDefaults) so the menu can show streak history.
public struct ResetRecord: Codable, Equatable, Sendable {
    /// Calendar day the streak was reset (start-of-day).
    public let endedOn: Date
    /// The streak's length at the moment of reset (its last displayed value).
    public let length: Int

    public init(endedOn: Date, length: Int) {
        self.endedOn = endedOn
        self.length = length
    }
}
