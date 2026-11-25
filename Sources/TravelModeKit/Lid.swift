import Foundation
import IOKit

/// Reads whether the MacBook's lid is closed.
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

    /// Turns the display off now, like pressing Control-Shift-Power. Needs no admin rights.
    public static func turnScreenOff() {
        Shell.run(SleepSystem.pmset, ["displaysleepnow"])
    }
}
