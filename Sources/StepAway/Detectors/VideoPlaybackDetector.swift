import AppKit

enum VideoClassifier {
    static func isPlayer(bundleID: String?, allowlist: [String]) -> Bool {
        guard let bundleID else { return false }
        return allowlist.contains(bundleID)
    }
}

/// A fullscreen window owned by a known video player means the user is watching
/// something, not working — pausing here avoids fighting the video.
@MainActor
final class VideoPlaybackDetector: Detector {
    let id = "video"
    let displayName = "视频播放"

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func evaluate() async -> DetectorVerdict? {
        let settings = store.value
        guard settings.videoDetectorEnabled else { return nil }

        for info in FullscreenWindowScanner.scan() {
            guard VideoClassifier.isPlayer(bundleID: info.bundleID, allowlist: settings.videoPlayerBundleIDs) else { continue }
            if let bundleID = info.bundleID, settings.ignoredBundleIDs.contains(bundleID) { continue }
            return DetectorVerdict(reason: "视频播放：\(info.owner)", subject: info.bundleID)
        }
        return nil
    }
}
