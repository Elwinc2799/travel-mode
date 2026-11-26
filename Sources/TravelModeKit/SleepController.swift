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

    /// What happens to the built-in screen when the lid closes At Desk. Screen off by default.
    @Published public var lidCloseAction: LidCloseAction {
        didSet {
            guard !isDemo else { return }
            UserDefaults.standard.set(lidCloseAction.rawValue, forKey: Self.lidActionKey)
            log.info("Lid-close action set to \(self.lidCloseAction.rawValue, privacy: .public)")
        }
    }

    /// The rattle as the board flips. On by default.
    @Published public var flipSound: Bool {
        didSet { saveSound(.flip, flipSound) }
    }
    /// Which click the flaps make.
    @Published public var flipSoundStyle: FlipSoundStyle {
        didSet {
            guard !isDemo else { return }
            UserDefaults.standard.set(flipSoundStyle.rawValue, forKey: FlipSoundStyle.defaultsKey)
            log.info("flip sound set to \(self.flipSoundStyle.title, privacy: .public)")
        }
    }
    /// Ticks during the sleep countdown. On by default.
    @Published public var countdownSound: Bool {
        didSet { saveSound(.countdown, countdownSound) }
    }

    /// When the Mac will sleep, during the short countdown before it does. Nil otherwise.
    @Published public private(set) var sleepingAt: Date? {
        didSet { onSleepCountdown?(sleepingAt) }
    }
    /// How long the countdown runs, so a hand still on the trackpad doesn't wake the Mac straight away.
    public static let sleepCountdown: TimeInterval = 2
    /// With VoiceOver on, long enough to hear the announcement and choose Cancel.
    public static let voiceOverSleepCountdown: TimeInterval = 10
    /// The length of the current (or last) countdown.
    @Published public private(set) var countdownLength: TimeInterval = SleepController.sleepCountdown

    /// The person chose "Not now" on the setup card.
    @Published public var setupDismissed: Bool {
        didSet { UserDefaults.standard.set(setupDismissed, forKey: Self.setupDismissedKey) }
    }

    /// Called when the charger is unplugged while At Desk, so the app can warn before it goes in a bag.
    public var onUnpluggedAtDesk: (() -> Void)?
    /// Called when the charger is plugged back in (the warning can go away).
    public var onPluggedIn: (() -> Void)?
    /// Called when the sleep countdown starts (with the moment it ends) or stops (nil).
    public var onSleepCountdown: ((Date?) -> Void)?

    private static let lidActionKey = "lidCloseAction"
    /// Earlier versions had an on/off switch for screen off; off now means dim.
    private static let oldScreenOffKey = "screenOffOnLidClose"
    /// The brightness before the lid closed, kept on disk so a quit or restart with the lid shut
    /// can't leave the screen dark.
    private static let savedBrightnessKey = "brightnessBeforeLidClosed"
    private static let setupDismissedKey = "setupDismissed"
    /// Demo controllers drive the README previews and never touch real settings or windows.
    public let isDemo: Bool
    private var timers: [Timer] = []
    private var lidWasClosed = false
    private var wasOnBattery = false
    private var sleepTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?

    /// A live controller, or a demo one (for previews) that never touches real settings.
    public init(demo: Mode? = nil, setUp: Bool = true, device: Device? = nil) {
        lidCloseAction = Self.savedLidCloseAction(demo: demo != nil)
        flipSound = demo != nil || Sounds.isEnabled(.flip)
        countdownSound = demo != nil || Sounds.isEnabled(.countdown)
        flipSoundStyle = demo != nil ? .original : FlipSoundStyle.saved
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
        if !Lid.isClosed() { restoreBrightness(reason: "launch") }
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
        // If the Mac sleeps some other way (the lid, the Apple menu) during the countdown, drop it;
        // otherwise it would finish on wake and send the Mac straight back to sleep.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Right away, not in a later task, so it's done before the Mac sleeps.
            MainActor.assumeIsolated { self?.cancelSleep() }
        }
        guard device.hasLid else { return }
        // Once a second: act only on the moment the lid closes or the charger is unplugged, so a
        // screen woken remotely (Screen Sharing, Sill) with the lid shut stays on.
        lidWasClosed = Lid.isClosed()
        wasOnBattery = Lid.isOnBattery()
        // Launched with the lid already shut (a restart, a login): act as if it had just closed.
        if lidWasClosed { lidClosed(reason: "lid closed at launch") }
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
        if closed, !lidWasClosed { lidClosed(reason: "Lid closed") }
        if !closed, lidWasClosed {
            log.info("Lid opened")
            restoreBrightness(reason: "lid opened")
        }
        if onBattery != wasOnBattery {
            let atDesk = SleepSystem.currentMode() == .desk
            log.info("Power source changed: \(onBattery ? "battery" : "charger", privacy: .public) (at desk: \(atDesk))")
            if onBattery, atDesk { onUnpluggedAtDesk?() }
            if !onBattery { onPluggedIn?() }
        }
    }

    private func saveSound(_ kind: Sounds.Kind, _ enabled: Bool) {
        guard !isDemo else { return }
        Sounds.setEnabled(kind, enabled)
        log.info("\(kind.rawValue, privacy: .public) sound turned \(enabled ? "on" : "off", privacy: .public)")
    }

    private func lidClosed(reason: String) {
        let external = Lid.externalDisplayActive()
        let atDesk = SleepSystem.currentMode() == .desk
        log.info("\(reason, privacy: .public) (at desk: \(atDesk), external display: \(external), action: \(self.lidCloseAction.rawValue, privacy: .public))")
        guard !external, atDesk else { return }
        // Without the brightness API, Dim can't work; fall back to screen off.
        if lidCloseAction == .dim, Brightness.isSupported { dimScreen() } else { Lid.turnScreenOff() }
    }

    private static func savedLidCloseAction(demo: Bool) -> LidCloseAction {
        let defaults = UserDefaults.standard
        if !demo, let raw = defaults.string(forKey: lidActionKey), let action = LidCloseAction(rawValue: raw) {
            return action
        }
        if !demo, let screenOff = defaults.object(forKey: oldScreenOffKey) as? Bool {
            return screenOff ? .screenOff : .dim
        }
        return .screenOff
    }

    private func dimScreen() {
        let defaults = UserDefaults.standard
        // Already dimmed (the lid bounced): keep the first saved value, the real one.
        if defaults.object(forKey: Self.savedBrightnessKey) == nil {
            guard let current = Brightness.get() else {
                log.error("Can't read the screen brightness; leaving it as it is")
                return
            }
            defaults.set(current, forKey: Self.savedBrightnessKey)
        }
        let dimmed = Brightness.set(0)
        log.info("Dimmed the screen (saved brightness \(defaults.float(forKey: Self.savedBrightnessKey)), ok: \(dimmed))")
    }

    /// Puts back the brightness saved when the lid closed, if any.
    public func restoreBrightness(reason: String) {
        guard !isDemo else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.savedBrightnessKey) != nil else { return }
        let saved = defaults.float(forKey: Self.savedBrightnessKey)
        if Brightness.set(saved) {
            defaults.removeObject(forKey: Self.savedBrightnessKey)
            log.info("Restored brightness \(saved) (\(reason, privacy: .public))")
        } else {
            log.error("Couldn't restore brightness \(saved) (\(reason, privacy: .public))")
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
        cancelSleep()
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

    /// One click to pack up: switch to Travelling (the panel shows it at once), then sleep after
    /// a short countdown.
    public func switchToTravellingAndSleep() {
        if mode == .desk, !switchMode() { return }
        startSleepCountdown()
    }

    /// Sleeps after a short countdown, which `cancelSleep()` stops.
    public func startSleepCountdown() {
        guard mode == .travelling, sleepingAt == nil else { return }
        let voiceOver = !isDemo && NSWorkspace.shared.isVoiceOverEnabled
        let duration = voiceOver ? Self.voiceOverSleepCountdown : Self.sleepCountdown
        countdownLength = duration
        sleepingAt = Date().addingTimeInterval(duration)
        log.info("Sleeping in \(Int(duration)) s (VoiceOver: \(voiceOver))")
        // High priority, so VoiceOver says it straight away instead of after the button it's on.
        // That cuts off VoiceOver reading the Cancel button's name, so the announcement says it.
        var announcement = AttributedString("Sleeping in \(Int(duration)) seconds. To stay awake, choose Cancel sleep.")
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
        guard !isDemo else { return }
        // A tick on each of the last few seconds shown (2, 1; or 3, 2, 1), then a soft tone just
        // before sleep. Fewer ticks keep them from talking over VoiceOver.
        let total = Int(duration)
        if total <= 3 { Sounds.playTick() }
        sleepTask = Task { @MainActor [weak self] in
            for second in 1...total {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.sleepingAt != nil else { return }
                if (1...3).contains(total - second) { Sounds.playTick() }
            }
            Sounds.playSleepTone()
            // Let the tone play before the Mac goes quiet. Still cancellable until then.
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.sleepingAt != nil else { return }
            self.sleepingAt = nil
            self.sleepTask = nil
            // The mode may have changed outside the app (the command line) during the countdown.
            self.refresh()
            self.sleepNow()
        }
    }

    public func cancelSleep() {
        guard sleepingAt != nil else { return }
        sleepTask?.cancel()
        sleepTask = nil
        sleepingAt = nil
        log.info("Sleep cancelled")
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

    /// Before quitting: put the Mac back to normal sleep and the screen back to its brightness, so
    /// nothing is left changed once the app (and its menu bar icon) is gone. Only for Quit in the
    /// panel; a restart or logout leaves At Desk on, so the Mac stays reachable afterwards.
    /// With the lid shut (and no external display) it stays At Desk: turning sleep on would put the
    /// Mac to sleep at once and cut off whoever quit it remotely.
    public func prepareToQuit() {
        guard !isDemo else { return }
        cancelSleep()
        restoreBrightness(reason: "quit")
        guard SleepSystem.currentMode() == .desk else { return }
        if Lid.isClosed(), !Lid.externalDisplayActive() {
            log.info("Kept At Desk on quit: the lid is closed, so turning sleep on would sleep the Mac at once")
            return
        }
        if SleepSystem.setWithoutPassword(.travelling) {
            log.info("Restored normal sleep on quit")
        } else if let error = SleepSystem.setWithAdminPrompt(.travelling) {
            log.error("Quit without restoring normal sleep: \(error, privacy: .public)")
        } else {
            log.info("Restored normal sleep on quit (with password)")
        }
    }
}
