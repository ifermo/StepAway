import Foundation

/// Daily allowance for skipping and postponing. Persisted next to the stats file
/// and reset whenever the local day changes.
@MainActor
final class QuotaStore {
    private struct Stored: Codable {
        var day: String
        var skips: Int
        var snoozeSeconds: TimeInterval
    }

    private let fileURL: URL
    private let clock: () -> Date
    private var stored: Stored

    init(fileURL: URL? = nil, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL ?? QuotaStore.defaultFileURL()
        self.clock = clock
        let today = QuotaStore.dayKey(for: clock())
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data),
           decoded.day == today {
            stored = decoded
        } else {
            stored = Stored(day: today, skips: 0, snoozeSeconds: 0)
        }
    }

    func remainingSkips(limit: Int) -> Int {
        rollIfNeeded()
        return max(0, limit - stored.skips)
    }

    func canSkip(limit: Int) -> Bool {
        remainingSkips(limit: limit) > 0
    }

    func recordSkip() {
        rollIfNeeded()
        stored.skips += 1
        persist()
    }

    func remainingSnooze(limit: TimeInterval) -> TimeInterval {
        rollIfNeeded()
        return max(0, limit - stored.snoozeSeconds)
    }

    func canSnooze(by seconds: TimeInterval, limit: TimeInterval) -> Bool {
        remainingSnooze(limit: limit) >= seconds
    }

    func recordSnooze(seconds: TimeInterval) {
        rollIfNeeded()
        stored.snoozeSeconds += seconds
        persist()
    }

    // MARK: - Helpers

    private func rollIfNeeded() {
        let today = QuotaStore.dayKey(for: clock())
        guard stored.day != today else { return }
        stored = Stored(day: today, skips: 0, snoozeSeconds: 0)
        persist()
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func defaultFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["STEPAWAY_QUOTA_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("StepAway", isDirectory: true)
            .appendingPathComponent("quotas.json")
    }
}
