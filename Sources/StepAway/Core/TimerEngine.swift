import Foundation

enum BreakKind: String, Codable, Equatable {
    case short
    case long

    var title: String { self == .short ? "Short break" : "Long break" }
}

enum PauseReason: Equatable {
    case manual
    case detected([String])

    var label: String {
        switch self {
        case .manual:
            return "Paused"
        case .detected(let reasons):
            return "Auto-paused: " + reasons.joined(separator: ", ")
        }
    }
}

@MainActor
final class TimerEngine {
    enum Phase: Equatable {
        case work
        case breaking(BreakKind)
        case paused(PauseReason)
        case stopped
    }

    struct Snapshot: Equatable {
        let phase: Phase
        let remaining: TimeInterval
        let total: TimeInterval
        let breaksSinceLong: Int
        let remainingSkips: Int
        let remainingSnooze: TimeInterval

        var clock: String {
            let value = max(0, Int(remaining.rounded(.up)))
            return String(format: "%d:%02d", value / 60, value % 60)
        }

        var isBreaking: Bool {
            if case .breaking = phase { return true }
            return false
        }
    }

    private let store: SettingsStore
    private let quota: QuotaStore
    private let clock: () -> Date
    private var offset: TimeInterval = 0

    var onChange: ((Snapshot) -> Void)?
    var onPhaseChange: ((_ from: Phase, _ to: Phase, _ at: Date) -> Void)?

    private var phase: Phase = .work
    private var deadline: Date
    private var pausedRemaining: TimeInterval = 0
    private var total: TimeInterval
    private var breaksSinceLong = 0
    private var pausedPhase: Phase?
    private var ticker: Task<Void, Never>?

    var settings: Settings { store.value }

    convenience init(settings: Settings, quota: QuotaStore, clock: @escaping () -> Date = { Date() }) {
        self.init(store: SettingsStore(settings), quota: quota, clock: clock)
    }

    init(store: SettingsStore, quota: QuotaStore, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.quota = quota
        self.clock = clock
        self.total = store.value.workDuration
        self.deadline = clock().addingTimeInterval(store.value.workDuration)
    }

    var now: Date { clock().addingTimeInterval(offset) }

    var snapshot: Snapshot {
        Snapshot(
            phase: phase,
            remaining: currentRemaining,
            total: total,
            breaksSinceLong: breaksSinceLong,
            remainingSkips: quota.remainingSkips(limit: settings.dailySkipLimit),
            remainingSnooze: quota.remainingSnooze(limit: settings.dailySnoozeLimitSeconds)
        )
    }

    private var currentRemaining: TimeInterval {
        switch phase {
        case .paused:
            return pausedRemaining
        case .stopped:
            return 0
        case .work, .breaking:
            return max(0, deadline.timeIntervalSince(now))
        }
    }

    var isRunning: Bool {
        if case .stopped = phase { return false }
        return true
    }

    var isBreaking: Bool {
        if case .breaking = phase { return true }
        return false
    }

    var canAutoPause: Bool { phase == .work }

    var isAutoPaused: Bool {
        if case .paused(.detected) = phase { return true }
        return false
    }

    // MARK: - Lifecycle

    func start() {
        guard ticker == nil else { return }
        if case .stopped = phase { phase = .work }
        scheduleWork()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
        publish()
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        pausedPhase = nil
        transition(to: .stopped)
    }

    /// Single state-advancing entry point. The ticker only refreshes the display;
    /// deadlines decide every transition, so sleep, stalls and clock changes cannot
    /// desynchronise the countdown.
    func refresh() {
        switch phase {
        case .paused, .stopped:
            return
        case .work, .breaking:
            break
        }

        var transitions = 0
        while now >= deadline {
            switch phase {
            case .work:
                beginBreak(breaksSinceLong + 1 >= settings.longBreakEvery ? .long : .short)
            case .breaking:
                finishBreak()
            default:
                publish()
                return
            }
            transitions += 1
            if transitions > 8 { break }
        }

        publish()
    }

    /// Test hook: shifts the engine's notion of "now" and advances the state.
    func advance(by seconds: TimeInterval) {
        offset += seconds
        refresh()
    }

    /// Extends every running deadline by the time the machine spent asleep.
    func handleSystemSleep(duration: TimeInterval) {
        guard settings.pauseOnSleep, duration > 0 else { return }
        switch phase {
        case .paused, .stopped:
            return
        case .work, .breaking:
            deadline = deadline.addingTimeInterval(duration)
        }
        publish()
    }

    // MARK: - Commands

    func pause(_ reason: PauseReason) {
        guard phase == .work else { return }
        pausedRemaining = currentRemaining
        pausedPhase = phase
        transition(to: .paused(reason))
    }

    func resume() {
        guard case .paused = phase, let restored = pausedPhase else { return }
        pausedPhase = nil
        deadline = now.addingTimeInterval(pausedRemaining)
        transition(to: restored)
    }

    @discardableResult
    func postpone(by seconds: TimeInterval) -> Bool {
        guard phase == .work,
              quota.canSnooze(by: seconds, limit: settings.dailySnoozeLimitSeconds)
        else { return false }

        quota.recordSnooze(seconds: seconds)
        deadline = deadline.addingTimeInterval(seconds)
        total = max(total, currentRemaining)
        publish()
        return true
    }

    func startBreakNow(_ kind: BreakKind) {
        guard !isBreaking else { return }
        pausedPhase = nil
        beginBreak(kind)
    }

    @discardableResult
    func skipBreak() -> Bool {
        guard isBreaking,
              quota.canSkip(limit: settings.dailySkipLimit)
        else { return false }

        quota.recordSkip()
        finishBreak()
        return true
    }

    // MARK: - Transitions

    private func beginBreak(_ kind: BreakKind) {
        total = duration(of: kind)
        deadline = now.addingTimeInterval(total)
        transition(to: .breaking(kind))
    }

    private func finishBreak() {
        guard case .breaking(let kind) = phase else { return }
        breaksSinceLong = kind == .long ? 0 : breaksSinceLong + 1
        scheduleWork()
        transition(to: .work)
    }

    private func scheduleWork() {
        total = settings.workDuration
        deadline = now.addingTimeInterval(total)
    }

    func duration(of kind: BreakKind) -> TimeInterval {
        kind == .long ? settings.longBreakDuration : settings.shortBreakDuration
    }

    private func transition(to newPhase: Phase) {
        let previous = phase
        phase = newPhase
        onPhaseChange?(previous, newPhase, now)
        publish()
    }

    private func publish() {
        onChange?(snapshot)
    }
}
