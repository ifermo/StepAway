import CoreGraphics
import Foundation

/// Uses the public "time since last input event" query, the same signal most
/// idle timers rely on; there is no notification-based alternative.
@MainActor
final class IdleDetector: Detector {
    let id = "idle"
    let displayName = "Idle"

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func evaluate() async -> DetectorVerdict? {
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~UInt32(0))!
        )
        guard idle >= store.value.idlePauseSeconds else { return nil }
        return DetectorVerdict(reason: "idle \(Int(idle / 60))m")
    }
}
