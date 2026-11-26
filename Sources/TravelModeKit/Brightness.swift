import CoreGraphics
import Foundation

/// Reads and sets the built-in screen's brightness.
///
/// macOS has no public API for this. It uses the private DisplayServices framework (as apps like
/// MonitorControl do), loaded at run time. If a future macOS drops it, `isSupported` is false and
/// Travel Mode simply leaves the brightness alone.
public enum Brightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: Getter, set: Setter)? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    /// This macOS has the brightness functions. (The built-in screen may still be offline, as in
    /// clamshell mode with an external display.)
    public static var isSupported: Bool { functions != nil }

    /// The built-in screen's brightness, 0...1, or nil if it can't be read.
    public static func get() -> Float? {
        guard let functions, let display = builtInDisplay() else { return nil }
        var value: Float = -1
        guard functions.get(display, &value) == 0, (0...1).contains(value) else { return nil }
        return value
    }

    /// Sets the built-in screen's brightness, 0...1. Returns true on success.
    @discardableResult
    public static func set(_ value: Float) -> Bool {
        guard let functions, let display = builtInDisplay() else { return false }
        return functions.set(display, min(1, max(0, value))) == 0
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

/// What happens to the built-in screen when the lid closes At Desk.
public enum LidCloseAction: String, CaseIterable, Sendable {
    /// Turn the screen off. Locks the Mac if a password is required after the display sleeps.
    case screenOff
    /// Dim the screen to its lowest brightness and restore it when the lid opens. Doesn't lock.
    case dim

    public var title: String {
        switch self {
        case .screenOff: "Turn screen off"
        case .dim: "Dim screen"
        }
    }

    public var caption: String {
        switch self {
        case .screenOff: "At Desk only. Also locks the Mac if a password is required after sleep. On battery, remote apps can't show the screen."
        case .dim: "At Desk only. The screen goes dark but stays on and unlocked, so remote-desktop apps keep working, even on battery. Brightness comes back when you open the lid."
        }
    }
}
