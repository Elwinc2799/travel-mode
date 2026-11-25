import AppKit
import Foundation
import ServiceManagement

/// Runs a command and returns its exit status and combined output.
enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Reads and changes the Mac's sleep setting (`pmset disablesleep`).
///
/// Changing it needs root. After a one-time setup, a sudo rule allows exactly two commands
/// without a password: `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. Without the rule,
/// macOS asks for an administrator password each time.
public enum SleepSystem {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"
    public static let ruleFile = "/etc/sudoers.d/travel-mode"

    /// The current mode, read from `pmset -g`.
    public static func currentMode() -> Mode {
        let result = Shell.run(pmset, ["-g"])
        for line in result.output.split(separator: "\n") where line.contains("SleepDisabled") {
            let value = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last
            return value == "1" ? .desk : .travelling
        }
        return .travelling
    }

    /// Switches without a password. Fails if the sudo rule isn't installed.
    @discardableResult
    public static func setWithoutPassword(_ mode: Mode) -> Bool {
        Shell.run(sudo, ["-n", pmset, "-a", "disablesleep", "\(mode.disableSleepValue)"]).status == 0
    }

    /// True when switching works without a password. Checks by re-applying the current value.
    public static func isSetUp() -> Bool {
        setWithoutPassword(currentMode())
    }

    /// True when this app's own rule file is installed (another rule may also grant the same commands).
    public static func hasOwnRule() -> Bool {
        FileManager.default.fileExists(atPath: ruleFile)
    }

    /// Switches with the macOS administrator prompt. Returns an error message, or nil on success.
    public static func setWithAdminPrompt(_ mode: Mode) -> String? {
        runAsAdmin("\(pmset) -a disablesleep \(mode.disableSleepValue)")
    }

    /// Installs the sudo rule for the current user. Returns an error message, or nil on success.
    public static func installRule() -> String? {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return "your account name has characters a sudo rule can't hold."
        }
        let lines = [
            "# Installed by Travel Mode (github.com/Elwinc2799/travel-mode).",
            "# Lets \(user) switch system sleep off and on without a password. Nothing else.",
            "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1",
        ]
        // Root writes the rule itself, into a root-owned staging file, so no other process can swap
        // the content between the check and the install. sudo ignores file names containing a dot,
        // so the staging file is never live. Check it, move it into place, re-check every rule;
        // on any failure both files are removed so sudo is never left broken.
        let staging = "/etc/sudoers.d/.travel-mode.new"
        let quoted = lines.map { "'\($0)'" }.joined(separator: " ")
        let command = "umask 0337 && /usr/bin/printf '%s\\n' \(quoted) > \(staging) && "
            + "/usr/sbin/chown root:wheel \(staging) && /bin/chmod 0440 \(staging) && "
            + "/usr/sbin/visudo -c -f \(staging) && /bin/mv -f \(staging) \(ruleFile) && "
            + "/usr/sbin/visudo -c || { /bin/rm -f \(staging) \(ruleFile); exit 1; }"
        return runAsAdmin(command)
    }

    /// Removes this app's sudo rule. Returns an error message, or nil on success.
    public static func removeRule() -> String? {
        runAsAdmin("/bin/rm -f \(ruleFile)")
    }

    /// Puts the Mac to sleep now. Only works while sleep is on (Travelling).
    public static func sleepNow() {
        Shell.run(pmset, ["sleepnow"])
    }

    static let cancelled = "cancelled"

    static func runAsAdmin(_ shellCommand: String) -> String? {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return cancelled }
        return (error[NSAppleScript.errorMessage] as? String) ?? "macOS refused the change."
    }
}

/// "Open at login", through the system's login items.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
