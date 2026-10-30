import Foundation

/// macOS ships no public "lock now" API. The supported path is the private
/// `SACLockScreenImmediate` in login.framework — the call behind ⌃⌘Q — so this
/// is the one place the app reaches outside the public SDK.
protocol ScreenLocker {
    /// Returns false when the screen could not be locked.
    @discardableResult
    func lockScreen() -> Bool
}

final class SACScreenLocker: ScreenLocker {
    private typealias LockFunction = @convention(c) () -> Int32

    private let lock: LockFunction?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
        if let symbol = handle.flatMap({ dlsym($0, "SACLockScreenImmediate") }) {
            lock = unsafeBitCast(symbol, to: LockFunction.self)
        } else {
            lock = nil
        }
    }

    @discardableResult
    func lockScreen() -> Bool {
        guard let lock else {
            Self.report("login.framework 里没有 SACLockScreenImmediate，退回到显示器睡眠")
            return Self.sleepDisplay()
        }
        let status = lock()
        guard status == 0 else {
            Self.report("SACLockScreenImmediate 返回 \(status)，退回到显示器睡眠")
            return Self.sleepDisplay()
        }
        return true
    }

    /// Degraded path for a macOS that drops the private symbol: still leaves the
    /// user staring at a dark screen instead of nothing happening at all.
    private static func sleepDisplay() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            report("pmset displaysleepnow 退出码 \(finished.terminationStatus)")
        }
        do {
            try process.run()
        } catch {
            report("无法启动 pmset：\(error.localizedDescription)")
            return false
        }
        return true
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("StepAway: 锁屏失败，\(message)\n".utf8))
    }
}
