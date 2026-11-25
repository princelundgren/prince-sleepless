import Foundation

/// The helper daemon's registration, as `SMAppService` reports it; the app maps `.notFound` to
/// `.notRegistered`.
public enum HelperStatus: Equatable, Sendable, Codable {
    case notRegistered
    case requiresApproval
    case enabled
}

/// A fresh read of the power state, sent with the launch, a user's switch and the schedule's
/// events. `.flagRead` and `.helper` carry none: an adoption from them arms a battery check at once.
public struct Readings: Equatable, Sendable {
    /// `nil` when the Mac has no internal battery or the power source couldn't be read.
    public var power: PowerSnapshot?
    public var lowPowerMode: Bool

    public init(power: PowerSnapshot?, lowPowerMode: Bool) {
        self.power = power
        self.lowPowerMode = lowPowerMode
    }
}

/// The user's settings.
public struct Preferences: Equatable, Sendable, Codable {
    /// The battery charge in percent at or under which keep-awake stops on battery.
    public var floor = 20
    public var lowPowerModeRule = true
    public var stayOnAfterRestart = false
    public var schedule: ScheduleWindow?

    public init(floor: Int = 20, lowPowerModeRule: Bool = true, stayOnAfterRestart: Bool = false, schedule: ScheduleWindow? = nil) {
        self.floor = floor
        self.lowPowerModeRule = lowPowerModeRule
        self.stayOnAfterRestart = stayOnAfterRestart
        self.schedule = schedule
    }

    /// These preferences held to the ranges Settings offers: the floor rounded to a step of 5
    /// within 5–50, and the schedule's times to hours 0–23 and minutes 0–59.
    public func clamped() -> Preferences {
        var clamped = self
        clamped.floor = (floor.clamped(to: 5...50) + 2) / 5 * 5
        if var schedule {
            schedule.start = schedule.start.clamped()
            schedule.end = schedule.end.clamped()
            clamped.schedule = schedule
        }
        return clamped
    }
}

/// What started the current keep-awake run.
public enum RunOrigin: String, Equatable, Sendable, Codable {
    case manual
    case manualWithTimer
    case schedule
    /// A flag found on that the app took over.
    case adopted
    /// Switched on again at launch after a restart; a run the schedule started keeps `.schedule`.
    case restored
}

/// Keep-awake was on when the system began a logout, restart or shutdown.
public struct PowerOffRecord: Equatable, Sendable, Codable {
    public var bootSession: UUID
    public var timerEnd: Date?

    public init(bootSession: UUID, timerEnd: Date?) {
        self.bootSession = bootSession
        self.timerEnd = timerEnd
    }
}

/// Everything the controller remembers between events and across launches.
public struct ControllerState: Equatable, Sendable, Codable {
    /// The system's sleep-disabled flag, as last read or set.
    public var flagOn = false
    /// The helper guards the flag, so it clears the flag if the app goes away.
    public var guarded = false
    public var origin: RunOrigin?
    /// When the current run was switched on; the schedule's end switches off a timer run only
    /// when this falls inside the window that is ending.
    public var runStartedAt: Date?
    public var timerEnd: Date?
    public var lastActedBoundary: Boundary?
    public var holdOffUntil: Date?
    /// Why keep-awake last ended or was refused; cleared by the next switch-on.
    public var lastOffReason: OffReason?
    /// An update is ready and installs at the next switch-off.
    public var updateWaiting = false
    /// The helper is re-registered at the next switch-off.
    public var reregisterPending = false
    public var powerOff: PowerOffRecord?
    /// The last power reading during the current run.
    public var lastPower: PowerSnapshot?
    /// Low Power Mode came on during the current run and is still on.
    public var lowPowerModeCameOn = false

    public init(
        flagOn: Bool = false,
        guarded: Bool = false,
        origin: RunOrigin? = nil,
        runStartedAt: Date? = nil,
        timerEnd: Date? = nil,
        lastActedBoundary: Boundary? = nil,
        holdOffUntil: Date? = nil,
        lastOffReason: OffReason? = nil,
        updateWaiting: Bool = false,
        reregisterPending: Bool = false,
        powerOff: PowerOffRecord? = nil,
        lastPower: PowerSnapshot? = nil,
        lowPowerModeCameOn: Bool = false
    ) {
        self.flagOn = flagOn
        self.guarded = guarded
        self.origin = origin
        self.runStartedAt = runStartedAt
        self.timerEnd = timerEnd
        self.lastActedBoundary = lastActedBoundary
        self.holdOffUntil = holdOffUntil
        self.lastOffReason = lastOffReason
        self.updateWaiting = updateWaiting
        self.reregisterPending = reregisterPending
        self.powerOff = powerOff
        self.lastPower = lastPower
        self.lowPowerModeCameOn = lowPowerModeCameOn
    }
}

/// What the app knows at launch.
public struct LaunchInfo: Equatable, Sendable {
    public var flagOn: Bool
    /// The app's build number differs from the one stored at the last launch.
    public var buildChanged: Bool
    public var bootSession: UUID
    /// `nil` at the first launch ever.
    public var lastBootSession: UUID?
    /// The last run of the app ended with a quit, not a crash.
    public var cleanQuit: Bool
    public var readings: Readings

    public init(flagOn: Bool, buildChanged: Bool, bootSession: UUID, lastBootSession: UUID?, cleanQuit: Bool, readings: Readings) {
        self.flagOn = flagOn
        self.buildChanged = buildChanged
        self.bootSession = bootSession
        self.lastBootSession = lastBootSession
        self.cleanQuit = cleanQuit
        self.readings = readings
    }
}

/// Something that happened, for the controller to decide on.
public enum Event: Sendable {
    case launched(LaunchInfo)
    case flagRead(Bool)
    case helper(HelperStatus)
    /// The helper's reply to the oldest `keepAwake`, `allowSleep` or `reguard` not yet replied
    /// to; a failed `reguard` comes as `.guardLost` instead. The app sends exactly one of the two
    /// for each of those commands, in the order they were returned.
    case helperReplied(ok: Bool)
    /// The helper process exited, or its connection was invalidated.
    case helperInterrupted
    /// A `reguard` failed: the flag is still on, and nothing guards it.
    case guardLost
    /// The helper reports a protocol version other than this build's.
    case helperOutdated
    case tapped(Readings)
    case picked(KeepAwakeDuration, Readings)
    case notificationAction(turnOn: Bool, Readings)
    case power(PowerSnapshot)
    case lowPowerMode(Bool)
    case batteryCheckDue(PowerSnapshot)
    case timerFired
    /// The boundary timer fired. The controller decides by the time it is given, so a fire that
    /// comes late acts on the latest boundary at that time, not on the one it carries.
    case boundary(Boundary, Readings)
    case woke(Readings)
    case clockChanged(Readings)
    case preferencesChanged(Preferences)
    case willPowerOff(bootSession: UUID)
    /// The app is quitting. Answered with `.save`, the point at which the app records a clean quit.
    case willTerminate
    case updateReady
}

/// Something for the app to do, in the order given.
public enum Command: Equatable, Sendable {
    case registerHelper
    /// Unregister the helper, then register it again.
    case reregisterHelper
    case openLoginItems
    case keepAwake
    case allowSleep
    /// Send `keepAwake` again for a run already on, after the helper was interrupted.
    case reguard
    case observePower(Bool)
    case holdActivity(Bool)
    /// Seconds until the next battery check, or `nil` to cancel it.
    case armBatteryCheck(TimeInterval?)
    case armTimer(Date?)
    case armBoundary(Boundary?)
    case notify(Notice)
    case requestNotificationAuthorization
    case setLaunchAtLogin(Bool)
    case installUpdate
    /// Store `ControllerState` and `Preferences`.
    case save
}

/// A notification for the user.
public enum Notice: Equatable, Sendable {
    case turnedOff(OffReason)
    case approveHelper
    case couldNotChange
    case scheduleReminder(Boundary.Kind)
}

extension TimeOfDay {
    var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    func clamped() -> TimeOfDay {
        TimeOfDay(hour: hour.clamped(to: 0...23), minute: minute.clamped(to: 0...59))
    }
}

extension KeepAwakeDuration {
    var isValid: Bool {
        switch self {
        case .indefinitely: true
        case .minutes(let minutes): minutes >= 1
        case .until(let time): time.isValid
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
