import Foundation
import SwiftUI

/// The app's state: which mode the Mac is in, whether setup is done, and the last problem.
@MainActor
public final class SleepController: ObservableObject {
    @Published public private(set) var mode: Mode
    @Published public private(set) var isSetUp: Bool
    @Published public private(set) var hasOwnRule: Bool
    @Published public var message: String?

    /// Turn the screen off the moment the lid closes while At Desk. On by default.
    @Published public var screenOffOnLidClose: Bool {
        didSet { UserDefaults.standard.set(screenOffOnLidClose, forKey: Self.screenOffKey) }
    }

    private static let screenOffKey = "screenOffOnLidClose"
    private let isDemo: Bool
    private var timer: Timer?
    private var lidTimer: Timer?
    private var lidWasClosed = false

    /// A live controller, or a demo one (for previews) that never touches real settings.
    /// The Mac this runs on, for wording ("MacBook Air keeps running…") and lid features.
    public let device: Device

    public init(demo: Mode? = nil, setUp: Bool = true, device: Device? = nil) {
        screenOffOnLidClose = UserDefaults.standard.object(forKey: Self.screenOffKey) as? Bool ?? true
        self.device = device ?? (demo == nil ? Device.current : Device(name: "MacBook Air", hasLid: true))
        if let demo {
            mode = demo
            isSetUp = setUp
            hasOwnRule = setUp
            isDemo = true
        } else {
            mode = SleepSystem.currentMode()
            isSetUp = SleepSystem.isSetUp()
            hasOwnRule = SleepSystem.hasOwnRule()
            isDemo = false
            // Something else (Terminal, another app) may change the setting; keep the icon honest.
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            // Check the lid once a second; act only on the moment it closes, so a screen woken
            // remotely (Sill, Screen Sharing) with the lid shut stays on.
            if self.device.hasLid {
                lidWasClosed = Lid.isClosed()
                lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkLid() }
                }
            }
        }
    }

    private func checkLid() {
        let closed = Lid.isClosed()
        defer { lidWasClosed = closed }
        guard closed, !lidWasClosed, screenOffOnLidClose else { return }
        // Read the real setting rather than the cached mode, in case it changed elsewhere.
        if SleepSystem.currentMode() == .desk { Lid.turnScreenOff() }
    }

    public func refresh() {
        guard !isDemo else { return }
        let current = SleepSystem.currentMode()
        if current != mode { mode = current }
    }

    public func switchMode() {
        let target = mode.other
        message = nil
        guard !isDemo else { mode = target; return }
        if SleepSystem.setWithoutPassword(target) {
            mode = target
            return
        }
        if let error = SleepSystem.setWithAdminPrompt(target), error != SleepSystem.cancelled {
            message = "Couldn't switch to \(target.title): \(error)"
        }
        refresh()
        isSetUp = SleepSystem.isSetUp()
    }

    public func setUp() {
        message = nil
        guard !isDemo else { isSetUp = true; hasOwnRule = true; return }
        if let error = SleepSystem.installRule(), error != SleepSystem.cancelled {
            message = "Setup didn't finish: \(error)"
        }
        isSetUp = SleepSystem.isSetUp()
        hasOwnRule = SleepSystem.hasOwnRule()
    }

    public func removePermission() {
        message = nil
        guard !isDemo else { isSetUp = false; hasOwnRule = false; return }
        if let error = SleepSystem.removeRule(), error != SleepSystem.cancelled {
            message = "Couldn't remove the permission: \(error)"
        }
        isSetUp = SleepSystem.isSetUp()
        hasOwnRule = SleepSystem.hasOwnRule()
    }

    public func sleepNow() {
        guard !isDemo, mode == .travelling else { return }
        SleepSystem.sleepNow()
    }
}
