import Foundation

struct DetectorVerdict: Equatable {
    let reason: String
    /// Bundle identifier of the app the verdict is about, when the detector can
    /// attribute one. Ignore lists only ever match on this stable identity.
    let subject: String?

    init(reason: String, subject: String? = nil) {
        self.reason = reason
        self.subject = subject
    }
}

/// A detector answers one question: should concentrated work be suspended right now?
/// Keep every detector cheap and side-effect free — they run on a short poll interval.
@MainActor
protocol Detector: AnyObject {
    var id: String { get }
    var displayName: String { get }
    func evaluate() async -> DetectorVerdict?
}

/// Requires a verdict to persist before acting, and a clean streak before resuming,
/// so one transient window or camera blip cannot flap the timer.
struct VerdictDebounce: Equatable {
    var requiredHits = 2
    var requiredMisses = 2
    private(set) var hits = 0
    private(set) var misses = 0

    mutating func register(active: Bool) {
        if active {
            hits += 1
            misses = 0
        } else {
            misses += 1
            hits = 0
        }
    }

    var shouldPause: Bool { hits >= requiredHits }
    var shouldResume: Bool { misses >= requiredMisses }
}

@MainActor
final class DetectorCoordinator {
    private let engine: TimerEngine
    private let store: SettingsStore
    private let detectors: [Detector]

    private var debounce = VerdictDebounce()
    private var task: Task<Void, Never>?

    init(engine: TimerEngine, store: SettingsStore, detectors: [Detector]) {
        self.engine = engine
        self.store = store
        self.detectors = detectors
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                let interval = self.store.value.detectorPollInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func poll() async {
        guard engine.isRunning, engine.canAutoPause || engine.isAutoPaused else { return }

        let ignored = Set(store.value.ignoredBundleIDs)
        var reasons: [String] = []
        for detector in detectors {
            guard let verdict = await detector.evaluate() else { continue }
            if let subject = verdict.subject, ignored.contains(subject) { continue }
            reasons.append(verdict.reason)
        }
        reasons.removeDuplicates()

        debounce.register(active: !reasons.isEmpty)

        if debounce.shouldPause, engine.canAutoPause {
            engine.pause(.detected(reasons))
        } else if debounce.shouldResume, engine.isAutoPaused {
            engine.resume()
        }
    }
}

private extension Array where Element: Hashable {
    mutating func removeDuplicates() {
        var seen = Set<Element>()
        self = filter { seen.insert($0).inserted }
    }
}
