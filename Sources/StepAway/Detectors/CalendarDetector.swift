import EventKit

@MainActor
final class CalendarDetector: Detector {
    let id = "calendar"
    let displayName = "Calendar event"

    private let store = EKEventStore()

    func evaluate() async -> DetectorVerdict? {
        guard await ensureAccess() else { return nil }

        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60),
            calendars: nil
        )
        let active = store.events(matching: predicate).first {
            !$0.isAllDay && $0.status != .canceled
        }
        guard let event = active else { return nil }
        return DetectorVerdict(reason: event.title ?? "Calendar event")
    }

    private func ensureAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess:
                return true
            case .notDetermined:
                return (try? await store.requestFullAccessToEvents()) ?? false
            default:
                return false
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized:
                return true
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    store.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            default:
                return false
            }
        }
    }
}
