import SwiftUI

/// The two states of the Mac, named the way people think about them.
public enum Mode: String, CaseIterable, Sendable {
    /// Sleep is off: the Mac keeps running with the lid shut (on a hub, reachable remotely).
    case desk
    /// Sleep is on: normal Mac behaviour, safe to put in a bag.
    case travelling

    public var title: String { self == .desk ? "At Desk" : "Travelling" }

    /// One line saying what this mode means for this Mac, e.g. "MacBook Air keeps running with the lid shut."
    public func detail(on device: Device) -> String {
        switch (self, device.hasLid) {
        case (.desk, true): return "\(device.name) keeps running with the lid shut."
        case (.desk, false): return "\(device.name) keeps running and never sleeps."
        case (.travelling, true): return "\(device.name) sleeps normally. Safe to pack."
        case (.travelling, false): return "\(device.name) sleeps normally."
        }
    }

    /// The menu bar symbol. A suitcase rather than an airplane, which would read as Airplane Mode.
    public var symbol: String { self == .desk ? "laptopcomputer" : "suitcase.rolling.fill" }

    /// Amber for At Desk (it never sleeps: take care), green for Travelling (safe).
    public func color(in scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.desk, .dark): return Theme.departureAmber
        case (.desk, _): return Theme.departureAmberDeep
        case (.travelling, .dark): return Theme.platformGreen
        case (.travelling, _): return Theme.platformGreenDeep
        }
    }

    public var other: Mode { self == .desk ? .travelling : .desk }

    /// The value for `pmset -a disablesleep`.
    var disableSleepValue: Int { self == .desk ? 1 : 0 }
}
