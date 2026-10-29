import AppKit

struct MeetingApp {
    let name: String
    let bundleID: String
}

/// Pure matching so the policy can be tested without touching NSWorkspace.
enum MeetingAppMatcher {
    static func firstMatch(bundleIDs: [String], running: [MeetingApp]) -> MeetingApp? {
        let wanted = Set(bundleIDs)
        return running.first { wanted.contains($0.bundleID) }
    }
}

/// macOS exposes no public "is another app capturing the screen" query, and the
/// capture indicator is not a queryable window. This detector therefore watches
/// for an active media session: a camera or microphone in use *and* a known
/// meeting client running. Recording tools that are merely open are ignored on
/// purpose — running is not recording.
@MainActor
final class ScreenSharingDetector: Detector {
    let id = "screenSharing"
    let displayName = "Meeting / screen sharing"

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func evaluate() async -> DetectorVerdict? {
        let settings = store.value
        guard settings.screenSharingDetectorEnabled else { return nil }
        guard MediaDeviceProbe.isAnyDeviceRunning() else { return nil }
        guard let app = MeetingAppMatcher.firstMatch(bundleIDs: settings.meetingAppBundleIDs, running: Self.runningApps()) else {
            return nil
        }
        return DetectorVerdict(reason: "\(app.name) · 会议/共享中", subject: app.bundleID)
    }

    private static func runningApps() -> [MeetingApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return MeetingApp(name: app.localizedName ?? bundleID, bundleID: bundleID)
        }
    }
}
