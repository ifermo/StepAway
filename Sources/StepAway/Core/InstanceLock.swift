import Darwin
import Foundation

/// Prevents two copies of the app from running at once (a second launch would
/// double the timers, menu items and stats writes). Uses an exclusive `flock`
/// so the guard works no matter which binary path was launched.
@MainActor
final class InstanceLock {
    private let url: URL
    private var descriptor: Int32 = -1

    init(url: URL? = nil) {
        self.url = url ?? InstanceLock.defaultURL()
    }

    @discardableResult
    func acquire() -> Bool {
        guard descriptor < 0 else { return true }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    static func defaultURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["STEPAWAY_LOCK_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("StepAway", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }
}
