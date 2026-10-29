import Foundation

enum OfficeHours {
    /// Supports windows that cross midnight (`start > end`). An empty weekday list
    /// means the window can never be active.
    static func isActive(
        date: Date,
        startHour: Int,
        endHour: Int,
        weekdays: [Int],
        calendar: Calendar = .current
    ) -> Bool {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let hour = components.hour else { return true }
        guard weekdays.contains(weekday) else { return false }

        let minute = components.minute ?? 0
        let now = hour * 60 + minute
        let start = max(0, min(23, startHour)) * 60
        let end = max(0, min(23, endHour)) * 60

        if start == end { return true }
        if start < end { return now >= start && now < end }
        return now >= start || now < end
    }
}

/// Outside the configured working window the timer stays paused instead of
/// counting down through the evening.
@MainActor
final class OfficeHoursDetector: Detector {
    let id = "officeHours"
    let displayName = "办公时间"

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func evaluate() async -> DetectorVerdict? {
        let settings = store.value
        guard settings.officeHoursEnabled else { return nil }
        let active = OfficeHours.isActive(
            date: Date(),
            startHour: settings.officeStartHour,
            endHour: settings.officeEndHour,
            weekdays: settings.officeWeekdays
        )
        return active ? nil : DetectorVerdict(reason: "非办公时间")
    }
}
