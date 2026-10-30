import AppKit

@main
enum StepAwayMain {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                exit(SelfTest.run())
            }
            dispatchMain()
        }
        let lock = InstanceLock()
        guard lock.acquire() else {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.example.stepaway")
                .first?
                .activate(options: [.activateAllWindows])
            FileHandle.standardError.write(Data("StepAway 已在运行，本次启动已退出。\n".utf8))
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        lock.release()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private var engine: TimerEngine!
    private var detectors: DetectorCoordinator!
    private var menuBar: MenuBarController!
    private var overlay: BreakOverlayController!
    private var hud: PreBreakHUD!
    private var sound: SoundPlayer!
    private var settingsWindow: SettingsWindowController?

    private let stats = StatsStore()
    private let quota = QuotaStore()
    private let screenLocker: ScreenLocker = SACScreenLocker()

    private var phaseStartedAt: Date?
    private var currentPhase: TimerEngine.Phase = .work
    private var lockGate = BreakLockGate()
    private var sleepStartedAt: Date?
    private var isDemo = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--demo") {
            isDemo = true
            store.setInMemory { settings in
                settings.workDuration = 8
                settings.shortBreakDuration = 6
                settings.longBreakDuration = 10
                settings.longBreakEvery = 2
                settings.idlePauseSeconds = 3600
                settings.preBreakLeadSeconds = 4
            }
        }

        engine = TimerEngine(store: store, quota: quota)
        overlay = BreakOverlayController(store: store, onSkip: { [weak self] in
            guard let self else { return }
            self.engine.skipBreak()
        })
        sound = SoundPlayer(store: store)
        hud = PreBreakHUD(onPostpone: { [weak self] in
            guard let self else { return }
            self.engine.postpone(by: self.store.value.postponeBy)
        })
        menuBar = MenuBarController(
            engine: engine,
            store: store,
            summaryProvider: { [weak self] in self?.stats.summary() ?? StatsStore.Summary() },
            currentAppBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        phaseStartedAt = Date()
        engine.onPhaseChange = { [weak self] previous, next, at in
            guard let self else { return }
            self.closeInterval(previous, at: at)
            self.currentPhase = next
            self.phaseStartedAt = at
            self.lockGate.reset()
            self.hud.hide()
            if case .breaking(_) = next { self.sound.playStart() }
            if case .breaking(_) = previous { self.sound.playEnd() }
        }

        engine.onChange = { [weak self] snapshot in
            guard let self else { return }
            self.menuBar.render(snapshot)
            if snapshot.isBreaking {
                let kind = self.breakKind(from: snapshot)
                self.overlay.show(
                    kind: kind,
                    remaining: snapshot.remaining,
                    total: snapshot.total,
                    style: self.resolvedStyle(for: snapshot),
                    remainingSkips: snapshot.remainingSkips
                )
                self.lockScreenIfDue(kind: kind, snapshot: snapshot)
            } else {
                self.overlay.hide()
            }
            let settings = self.store.value
            self.hud.sync(
                enabled: settings.preBreakHUDEnabled,
                isWorking: snapshot.phase == .work,
                remaining: snapshot.remaining,
                lead: settings.preBreakLeadSeconds
            )
        }

        detectors = DetectorCoordinator(engine: engine, store: store, detectors: makeDetectors())

        observeSleep()
        engine.start()
        detectors.start()

        if CommandLine.arguments.contains("--open-settings") {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        detectors.stop()
        overlay.hide()
        hud.hide()
        closeInterval(currentPhase, at: Date())
        if !isDemo { store.value.save() }
    }

    // MARK: - Settings

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                store: store,
                engine: engine,
                onPreviewSound: { [weak self] name in self?.sound.preview(name) }
            )
        }
        settingsWindow?.show()
    }

    // MARK: - Sleep

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        sleepStartedAt = Date()
    }

    @objc private func systemDidWake() {
        guard let start = sleepStartedAt else { return }
        engine.handleSystemSleep(duration: Date().timeIntervalSince(start))
        sleepStartedAt = nil
    }

    // MARK: - Stats

    private func closeInterval(_ phase: TimerEngine.Phase, at date: Date) {
        guard let start = phaseStartedAt else { return }
        let record: StatsRecord.Kind?
        switch phase {
        case .work:
            record = .work
        case .breaking(let kind):
            record = kind == .long ? .longBreak : .shortBreak
        case .paused, .stopped:
            record = nil
        }
        if let record {
            stats.append(StatsRecord(kind: record, start: start, end: date))
        }
    }

    private func resolvedStyle(for snapshot: TimerEngine.Snapshot) -> OverlayStyle {
        if let raw = ProcessInfo.processInfo.environment["STEPAWAY_STYLE"],
           let style = OverlayStyle(rawValue: raw) {
            return style
        }
        return OverlayStyle.resolve(preference: store.value.overlayStyle, cycleIndex: snapshot.breaksSinceLong)
    }

    private func breakKind(from snapshot: TimerEngine.Snapshot) -> BreakKind {
        if case .breaking(let kind) = snapshot.phase { return kind }
        return .short
    }

    /// Long breaks lock the screen once the skip grace window has passed, so the
    /// enforced part of the break starts after the user's chance to opt out.
    private func lockScreenIfDue(kind: BreakKind, snapshot: TimerEngine.Snapshot) {
        let elapsed = snapshot.total - snapshot.remaining
        guard lockGate.shouldLockScreen(
            kind: kind,
            enabled: store.value.lockScreenDuringLongBreak,
            elapsed: elapsed
        ) else { return }
        screenLocker.lockScreen()
    }

    private func makeDetectors() -> [Detector] {
        var list: [Detector] = [
            IdleDetector(store: store),
            VideoPlaybackDetector(store: store),
            FullscreenAppDetector(store: store),
            DeepFocusAppDetector(store: store),
            OfficeHoursDetector(store: store)
        ]
        if store.value.calendarDetectorEnabled {
            list.append(CalendarDetector())
        }
        if store.value.screenSharingDetectorEnabled {
            list.append(ScreenSharingDetector(store: store))
        }
        return list
    }
}
