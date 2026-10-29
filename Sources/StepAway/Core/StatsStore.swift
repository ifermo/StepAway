import Foundation

struct StatsRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case work
        case shortBreak
        case longBreak
    }

    var kind: Kind
    var start: Date
    var end: Date

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

final class StatsStore {
    struct Summary {
        var workSeconds: TimeInterval = 0
        var breakCount: Int = 0
        var longestWorkSeconds: TimeInterval = 0

        var text: String {
            let minutes = Int((workSeconds / 60).rounded())
            return "今日专注 \(minutes)m · 休息 \(breakCount) 次"
        }
    }

    private(set) var records: [StatsRecord] = []
    private let fileURL: URL
    private let calendar = Calendar.current

    init(fileURL: URL = StatsStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    func append(_ record: StatsRecord) {
        guard record.seconds >= 1 else { return }
        records.append(record)
        if records.count > 5000 {
            records.removeFirst(records.count - 5000)
        }
        save()
    }

    func summary(for day: Date = Date()) -> Summary {
        var summary = Summary()
        for record in records where calendar.isDate(record.start, inSameDayAs: day) {
            switch record.kind {
            case .work:
                summary.workSeconds += record.seconds
                summary.longestWorkSeconds = max(summary.longestWorkSeconds, record.seconds)
            case .shortBreak, .longBreak:
                summary.breakCount += 1
            }
        }
        return summary
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["STEPAWAY_STATS_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("StepAway", isDirectory: true)
            .appendingPathComponent("stats.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StatsRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
