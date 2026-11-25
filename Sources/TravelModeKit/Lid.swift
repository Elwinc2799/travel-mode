import CoreGraphics
import Foundation
import IOKit
import IOKit.ps

/// Reads whether the MacBook's lid is closed, and whether it's running on battery.
///
/// With sleep disabled (At Desk), macOS keeps the built-in screen lit after the lid closes, until the
/// normal display-sleep timer runs out. Travel Mode watches for the lid closing and turns the screen
/// off straight away, which also locks the Mac if a password is required after the display sleeps.
public enum Lid {
    /// True when the lid is closed. False on Macs without a lid, or if it can't be read.
    public static func isClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                                    kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }

    /// True when a display other than the built-in one is connected and on, as in clamshell
    /// mode with an external monitor. Turning the screen off then would blank that monitor too.
    public static func externalDisplayActive() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsAsleep($0) == 0 }
    }

    /// Turns the display off now, like pressing Control-Shift-Power. Needs no admin rights.
    public static func turnScreenOff() {
        Shell.run(SleepSystem.pmset, ["displaysleepnow"])
    }

    /// True when running on battery, false on the charger (or on a Mac without a battery).
    public static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else {
            return false
        }
        return type == kIOPSBatteryPowerValue
    }
}
