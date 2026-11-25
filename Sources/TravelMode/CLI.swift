import Foundation
import TravelModeKit

enum CLI {
    static let options: Set<String> = ["--status", "--info", "--desk", "--travel", "--help", "-h"]

    static let usage = """
    Usage: TravelMode [--status | --info | --desk | --travel | --help]
      --status   Print the current mode: "desk" or "travelling".
      --info     Describe the mode, this Mac, and whether setup is done.
      --desk     At Desk: sleep off, the Mac keeps running with the lid shut.
      --travel   Travelling: sleep on, normal Mac behaviour.
    Run without options to open the menu bar app.
    """

    static func run(_ argument: String) -> Int32 {
        switch argument {
        case "--status":
            print(SleepSystem.currentMode().rawValue)
            return 0
        case "--info":
            let device = Device.detailed()
            let mode = SleepSystem.currentMode()
            print("\(mode.title): \(mode.detail(on: device))")
            print("Device: \(device.name), lid: \(device.hasLid ? "yes" : "no")")
            print("Switch without password: \(SleepSystem.isSetUp() ? "yes" : "no")")
            return 0
        case "--desk":
            return set(.desk)
        case "--travel":
            return set(.travelling)
        case "--help", "-h":
            print(usage)
            return 0
        default:
            FileHandle.standardError.write(Data("Unknown option \(argument).\n\(usage)\n".utf8))
            return 2
        }
    }

    private static func set(_ mode: Mode) -> Int32 {
        if SleepSystem.setWithoutPassword(mode) {
            print(mode.rawValue)
            return 0
        }
        FileHandle.standardError.write(Data("""
        Couldn't switch without a password. Open Travel Mode and choose Set up, \
        or run: sudo pmset -a disablesleep \(mode == .desk ? 1 : 0)\n
        """.utf8))
        return 1
    }
}
