import AppKit

/// Fullscreen windows that are not a known video player. Games and immersive apps
/// land here; the split exists so the two cases can be enabled independently.
@MainActor
final class FullscreenAppDetector: Detector {
    let id = "fullscreen"
    let displayName = "全屏应用"

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func evaluate() async -> DetectorVerdict? {
        let settings = store.value
        guard settings.fullscreenDetectorEnabled else { return nil }

        let ignored = Set(settings.ignoredBundleIDs)
        let videoPlayers = Set(settings.videoPlayerBundleIDs)
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        for info in FullscreenWindowScanner.scan() {
            if let bundleID = info.bundleID {
                if ignored.contains(bundleID) { continue }
                if videoPlayers.contains(bundleID) { continue }
                if settings.excludeFrontmostApp, bundleID == frontmost { continue }
            }
            return DetectorVerdict(reason: "全屏应用：\(info.owner)", subject: info.bundleID)
        }
        return nil
    }
}
