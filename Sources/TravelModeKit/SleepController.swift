import AppKit
import Foundation
import SwiftUI

/// The app's state: which mode the Mac is in, whether setup is done, and the last problem.
@MainActor
public final class SleepController: ObservableObject {
    @Published public private(set) var mode: Mode
    @Published public private(set) var isSetUp: Bool
    @Published public private(set) var hasOwnRule: Bool
    @Published public var message: String?
    /// The Mac this runs on, for wording ("MacBook Air keeps running…") and lid features.
    @Published public private(set) var device: Device

    /// Turn the screen off the moment the lid closes while At Desk. On by default.
    @Published public var screenOffOnLidClose: Bool {
        didSet { UserDefaults.standard.set(screenOffOnLidClose, forKey: Self.screenOffKey) }
    }

    /// The person chose "Not now" on the setup card.
    @Published public var setupDismissed: Bool {
        didSet { UserDefaults.standard.set(setupDismissed, forKey: Self.setupDismissedKey) }
    }

    /// Called when the charger is unplugged while At Desk, so the app can warn before it goes in a bag.
    public var onUnpluggedAtDesk: (() -> Void)?
    /// Called when the charger is plugged back in (the warning can go away).
    public var onPluggedIn: (() -> Void)?

    private static let screenOffKey = "screenOffOnLidClose"
    private static let setupDismissedKey = "setupDismissed"
    /// Demo controllers drive the README previews and never touch real settings or windows.
    public let isDemo: Bool
    private var timers: [Timer] = []
    private var lidWasClosed = false
    private var wasOnBattery = false

    /// A live controller, or a demo one (for previews) that never touches real settings.
    public init(demo: Mode? = nil, setUp: Bool = true, device: Device? = nil) {
        screenOffOnLidClose = UserDefaults.standard.object(forKey: Self.screenOffKey) as? Bool ?? true
        setupDismissed = demo == nil && UserDefaults.standard.bool(forKey: Self.setupDismissedKey)
        if let demo {
            self.device = device ?? Device(name: "MacBook Air", hasLid: true)
            mode = demo
            isSetUp = setUp
            hasOwnRule = setUp
            isDemo = true
            return
        }
        self.device = device ?? Device.quick()
        mode = SleepSystem.currentMode()
        isSetUp = SleepSystem.isSetUp()
        hasOwnRule = SleepSystem.hasOwnRule()
        isDemo = false
        startWatching()
        // The everyday model name can take a moment to look up the first time; don't hold up launch.
        Task.detached(priority: .utility) {
            let detailed = Device.detailed()
            await MainActor.run { [weak self] in
                if let self, self.device != detailed { self.device = detailed }
            }
        }
    }

    private func startWatching() {
        // Something else (Terminal, another app) may change the setting; keep the icon honest.
        timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        guard device.hasLid else { return }
        // Once a second: act only on the moment the lid closes or the charger is unplugged, so a
        // screen woken remotely (Screen Sharing, Sill) with the lid shut stays on.
        lidWasClosed = Lid.isClosed()
        wasOnBattery = Lid.isOnBattery()
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchLidAndPower() }
        })
    }

    private func watchLidAndPower() {
        let closed = Lid.isClosed()
        let onBattery = Lid.isOnBattery()
        defer {
            lidWasClosed = closed
            wasOnBattery = onBattery
        }
        if closed, !lidWasClosed {
            let external = Lid.externalDisplayActive()
            let atDesk = SleepSystem.currentMode() == .desk
            log.info("Lid closed (at desk: \(atDesk), external display: \(external), screen-off option: \(self.screenOffOnLidClose))")
            if screenOffOnLidClose, !external, atDesk { Lid.turnScreenOff() }
        }
        if onBattery != wasOnBattery {
            let atDesk = SleepSystem.currentMode() == .desk
            log.info("Power source changed: \(onBattery ? "battery" : "charger", privacy: .public) (at desk: \(atDesk))")
            if onBattery, atDesk { onUnpluggedAtDesk?() }
            if !onBattery { onPluggedIn?() }
        }
    }

    public func refresh() {
        guard !isDemo else { return }
        let current = SleepSystem.currentMode()
        if current != mode { mode = current }
    }

    /// Switches to the other mode. Returns true when the switch happened.
    @discardableResult
    public func switchMode() -> Bool {
        let target = mode.other
        message = nil
        guard !isDemo else { mode = target; return true }
        if SleepSystem.setWithoutPassword(target) {
            mode = target
        } else {
            if let error = SleepSystem.setWithAdminPrompt(target), error != SleepSystem.cancelled {
                message = "Couldn't switch to \(target.title): \(error)"
            }
            refresh()
            isSetUp = SleepSystem.isSetUp()
        }
        guard mode == target else {
            log.error("Switch to \(target.rawValue, privacy: .public) failed or was cancelled")
            return false
        }
        log.info("Switched to \(target.rawValue, privacy: .public)")
        AccessibilityNotification.Announcement("Now \(target.title). \(target.detail(on: device))").post()
        return true
    }

    /// One click to pack up: switch to Travelling, then sleep.
    public func switchToTravellingAndSleep() {
        if mode == .desk, !switchMode() { return }
        sleepNow()
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
            message = "Couldn't turn the password back on: \(error)"
        }
        isSetUp = SleepSystem.isSetUp()
        hasOwnRule = SleepSystem.hasOwnRule()
    }

    public func sleepNow() {
        guard !isDemo, mode == .travelling else { return }
        SleepSystem.sleepNow()
    }
}
