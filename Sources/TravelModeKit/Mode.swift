import SwiftUI

/// The two states of the Mac, named the way people think about them.
public enum Mode: String, CaseIterable, Sendable {
    /// Sleep is off: the Mac keeps running with the lid shut (on a hub, reachable remotely).
    case desk
    /// Sleep is on: normal Mac behaviour, safe to put in a bag.
    case travelling

    public var title: String { self == .desk ? "At Desk" : "Travelling" }

    /// One line saying what this mode means for this Mac, e.g. "MacBook Air keeps running with the lid shut".
    public func detail(on device: Device) -> String {
        switch (self, device.hasLid) {
        case (.desk, true): return "\(device.name) keeps running with the lid shut"
        case (.desk, false): return "\(device.name) keeps running and never sleeps"
        case (.travelling, true): return "\(device.name) sleeps normally. Safe to pack."
        case (.travelling, false): return "\(device.name) sleeps normally"
        }
    }

    public var symbol: String { self == .desk ? "laptopcomputer" : "airplane" }

    public var color: Color { self == .desk ? Theme.platformGreen : Theme.departureAmber }

    public var other: Mode { self == .desk ? .travelling : .desk }

    /// The value for `pmset -a disablesleep`.
    var disableSleepValue: Int { self == .desk ? 1 : 0 }
}
