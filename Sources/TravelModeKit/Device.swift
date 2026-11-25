import Foundation
import IOKit

/// The Mac this runs on: its everyday name ("MacBook Air", "Mac mini") and whether it has a lid.
public struct Device: Sendable, Equatable {
    public let name: String
    public let hasLid: Bool

    public init(name: String, hasLid: Bool) {
        self.name = name
        self.hasLid = hasLid
    }

    /// Instant: the cached everyday name, or one guessed from the model identifier. Never blocks.
    public static func quick() -> Device {
        let model = modelIdentifier()
        let name = UserDefaults.standard.string(forKey: cacheKey(model)) ?? nameFromIdentifier(model)
        return Device(name: name, hasLid: lidExists())
    }

    /// The full answer, asking System Information if the name isn't cached yet. Can take a second
    /// or two the first time, so the app calls it off the main thread.
    public static func detailed() -> Device {
        let model = modelIdentifier()
        let key = cacheKey(model)
        if let cached = UserDefaults.standard.string(forKey: key) {
            return Device(name: cached, hasLid: lidExists())
        }
        if let name = systemProfilerName() {
            UserDefaults.standard.set(name, forKey: key) // only cache real answers
            return Device(name: name, hasLid: lidExists())
        }
        return Device(name: nameFromIdentifier(model), hasLid: lidExists())
    }

    private static func cacheKey(_ model: String) -> String { "deviceName.\(model)" }

    private static func modelIdentifier() -> String { sysctlString("hw.model") ?? "" }

    /// Newer Macs report a bare identifier such as "Mac16,10", so the everyday name comes from
    /// System Information.
    private static func systemProfilerName() -> String? {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"])
        guard result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
              let items = json["SPHardwareDataType"] as? [[String: Any]],
              let name = items.first?["machine_name"] as? String,
              !name.isEmpty else { return nil }
        return name
    }

    /// Fallback for identifiers such as "MacBookAir10,1" or "Macmini9,1"; newer ones give "Mac".
    static func nameFromIdentifier(_ model: String) -> String {
        let known: [(prefix: String, name: String)] = [
            ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"), ("iMacPro", "iMac Pro"), ("iMac", "iMac"), ("MacPro", "Mac Pro"),
        ]
        return known.first { model.hasPrefix($0.prefix) }?.name ?? "Mac"
    }

    /// Laptops publish a lid ("clamshell") state; desktops don't.
    private static func lidExists() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                               kCFAllocatorDefault, 0) != nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
