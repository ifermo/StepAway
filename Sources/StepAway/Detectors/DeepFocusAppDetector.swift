import AppKit

enum FocusMatcher {
    static func matches(frontmost: String?, focusApps: [String]) -> Bool {
        guard let frontmost else { return false }
        return focusApps.contains(frontmost)
    }
}

/// While one of the user's focus apps is in front, treat the session as
/// concentrated work and do not interrupt with a break.
@MainActor
final class DeepFocusAppDetector: Detector {
    let id = "deepFocus"
    let displayName = "专注应用"

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func evaluate() async -> DetectorVerdict? {
        let settings = store.value
        guard settings.deepFocusDetectorEnabled else { return nil }
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard FocusMatcher.matches(frontmost: frontmost?.bundleIdentifier, focusApps: settings.focusAppBundleIDs) else {
            return nil
        }
        let name = frontmost?.localizedName ?? "专注应用"
        return DetectorVerdict(reason: "专注：\(name)", subject: frontmost?.bundleIdentifier)
    }
}
