import Foundation

struct Settings: Codable, Equatable {
    var workDuration: TimeInterval = 20 * 60
    var shortBreakDuration: TimeInterval = 20
    var longBreakDuration: TimeInterval = 5 * 60
    var longBreakEvery: Int = 4

    var idlePauseSeconds: TimeInterval = 5 * 60
    var postponeBy: TimeInterval = 5 * 60
    var detectorPollInterval: TimeInterval = 5

    /// Mirrors the `NSWindow.sharingType = .none` trick that keeps the overlay out of screen recordings.
    var hideOverlayFromScreenCapture: Bool = true

    var calendarDetectorEnabled: Bool = true
    var screenSharingDetectorEnabled: Bool = true
    var meetingAppBundleIDs: [String] = Settings.defaultMeetingApps

    // P0 additions
    var pauseOnSleep: Bool = true
    var lockScreenDuringLongBreak: Bool = true
    var dailySkipLimit: Int = 3
    var dailySnoozeLimitSeconds: TimeInterval = 30 * 60
    var preBreakHUDEnabled: Bool = true
    var preBreakLeadSeconds: TimeInterval = 60
    var soundEnabled: Bool = true
    var soundVolume: Double = 0.6
    var soundStartName: String = "Glass"
    var soundEndName: String = "Ping"
    var ignoredBundleIDs: [String] = []
    var excludeFrontmostApp: Bool = true
    var overlayStyle: String = "auto"

    // Detectors
    var fullscreenDetectorEnabled: Bool = true
    var videoDetectorEnabled: Bool = true
    var videoPlayerBundleIDs: [String] = Settings.defaultVideoPlayers
    var deepFocusDetectorEnabled: Bool = false
    var focusAppBundleIDs: [String] = []
    var officeHoursEnabled: Bool = false
    var officeStartHour: Int = 9
    var officeEndHour: Int = 18
    var officeWeekdays: [Int] = [2, 3, 4, 5, 6]
}

extension Settings {
    /// Dedicated meeting clients only: browsers are excluded so an idle Chrome
    /// window cannot be mistaken for a call.
    static let defaultMeetingApps = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.apple.FaceTime",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "com.tencent.meeting",
        "com.bytedance.macos.feishu",
        "com.electron.lark",
        "com.alibaba.DingTalkMac"
    ]

    static let defaultVideoPlayers = [
        "com.colliderli.iina",
        "org.videolan.vlc",
        "io.mpv",
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "com.plexapp.plex",
        "com.firecore.infuse"
    ]

    private static let key = "StepAway.settings"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// Tolerates settings written by earlier builds: missing keys keep their defaults
// instead of resetting every value.
extension Settings {
    private enum CodingKeys: String, CodingKey {
        case workDuration, shortBreakDuration, longBreakDuration, longBreakEvery
        case idlePauseSeconds, postponeBy, detectorPollInterval, hideOverlayFromScreenCapture
        case calendarDetectorEnabled, screenSharingDetectorEnabled, meetingAppBundleIDs
        case pauseOnSleep, lockScreenDuringLongBreak, dailySkipLimit, dailySnoozeLimitSeconds
        case preBreakHUDEnabled, preBreakLeadSeconds
        case soundEnabled, soundVolume, soundStartName, soundEndName
        case ignoredBundleIDs, excludeFrontmostApp, overlayStyle
        case fullscreenDetectorEnabled, videoDetectorEnabled, videoPlayerBundleIDs
        case deepFocusDetectorEnabled, focusAppBundleIDs
        case officeHoursEnabled, officeStartHour, officeEndHour, officeWeekdays
    }

    init(from decoder: Decoder) throws {
        let defaults = Settings()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }

        self.init(
            workDuration: value(.workDuration, defaults.workDuration),
            shortBreakDuration: value(.shortBreakDuration, defaults.shortBreakDuration),
            longBreakDuration: value(.longBreakDuration, defaults.longBreakDuration),
            longBreakEvery: value(.longBreakEvery, defaults.longBreakEvery),
            idlePauseSeconds: value(.idlePauseSeconds, defaults.idlePauseSeconds),
            postponeBy: value(.postponeBy, defaults.postponeBy),
            detectorPollInterval: value(.detectorPollInterval, defaults.detectorPollInterval),
            hideOverlayFromScreenCapture: value(.hideOverlayFromScreenCapture, defaults.hideOverlayFromScreenCapture),
            calendarDetectorEnabled: value(.calendarDetectorEnabled, defaults.calendarDetectorEnabled),
            screenSharingDetectorEnabled: value(.screenSharingDetectorEnabled, defaults.screenSharingDetectorEnabled),
            meetingAppBundleIDs: value(.meetingAppBundleIDs, defaults.meetingAppBundleIDs),
            pauseOnSleep: value(.pauseOnSleep, defaults.pauseOnSleep),
            lockScreenDuringLongBreak: value(.lockScreenDuringLongBreak, defaults.lockScreenDuringLongBreak),
            dailySkipLimit: value(.dailySkipLimit, defaults.dailySkipLimit),
            dailySnoozeLimitSeconds: value(.dailySnoozeLimitSeconds, defaults.dailySnoozeLimitSeconds),
            preBreakHUDEnabled: value(.preBreakHUDEnabled, defaults.preBreakHUDEnabled),
            preBreakLeadSeconds: value(.preBreakLeadSeconds, defaults.preBreakLeadSeconds),
            soundEnabled: value(.soundEnabled, defaults.soundEnabled),
            soundVolume: value(.soundVolume, defaults.soundVolume),
            soundStartName: value(.soundStartName, defaults.soundStartName),
            soundEndName: value(.soundEndName, defaults.soundEndName),
            ignoredBundleIDs: value(.ignoredBundleIDs, defaults.ignoredBundleIDs),
            excludeFrontmostApp: value(.excludeFrontmostApp, defaults.excludeFrontmostApp),
            overlayStyle: value(.overlayStyle, defaults.overlayStyle),
            fullscreenDetectorEnabled: value(.fullscreenDetectorEnabled, defaults.fullscreenDetectorEnabled),
            videoDetectorEnabled: value(.videoDetectorEnabled, defaults.videoDetectorEnabled),
            videoPlayerBundleIDs: value(.videoPlayerBundleIDs, defaults.videoPlayerBundleIDs),
            deepFocusDetectorEnabled: value(.deepFocusDetectorEnabled, defaults.deepFocusDetectorEnabled),
            focusAppBundleIDs: value(.focusAppBundleIDs, defaults.focusAppBundleIDs),
            officeHoursEnabled: value(.officeHoursEnabled, defaults.officeHoursEnabled),
            officeStartHour: value(.officeStartHour, defaults.officeStartHour),
            officeEndHour: value(.officeEndHour, defaults.officeEndHour),
            officeWeekdays: value(.officeWeekdays, defaults.officeWeekdays)
        )
    }
}
