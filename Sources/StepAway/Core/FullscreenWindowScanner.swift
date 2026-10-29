import AppKit
import CoreGraphics

/// Lists windows that cover an entire screen, which is the shared signal for the
/// video and fullscreen-app detectors.
@MainActor
enum FullscreenWindowScanner {
    struct Info: Equatable {
        let owner: String
        let bundleID: String?
    }

    private static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "Control Center", "Notification Center",
        "Spotlight", "SystemUIServer", "StepAway"
    ]

    static func scan() -> [Info] {
        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return [] }
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var results: [Info] = []
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  !ignoredOwners.contains(owner),
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }

            guard screens.contains(where: { rect.contains($0) }) else { continue }

            let pid = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bundleID = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
            results.append(Info(owner: owner, bundleID: bundleID))
        }
        return results
    }
}
