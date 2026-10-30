import Foundation

/// Deterministic acceptance checks for the non-visual parts of the MVP.
/// Run with `StepAway --selftest`; exit code is the number of failures.
enum SelfTest {
    @MainActor
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            if condition {
                print("PASS  \(name)")
            } else {
                failures += 1
                print("FAIL  \(name) \(detail())")
            }
        }

        let base = Date(timeIntervalSince1970: 1_800_000_000)

        // 1. Work timer reaching zero starts a short break, and the break returns to work.
        do {
            var settings = Settings()
            settings.workDuration = 3
            settings.shortBreakDuration = 2
            settings.longBreakEvery = 4
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            engine.advance(by: 3)
            guard case .breaking(let kind) = engine.snapshot.phase else {
                check("work→break transition", false, "phase=\(engine.snapshot.phase)")
                return Int32(failures)
            }
            check("work→break transition", kind == .short)
            check("break total duration", engine.snapshot.total == 2, "total=\(engine.snapshot.total)")
            engine.advance(by: 2)
            check("break→work transition", engine.snapshot.phase == .work)
            check("work duration restored", engine.snapshot.remaining == 3, "remaining=\(engine.snapshot.remaining)")
        }

        // 2. Long break cadence.
        do {
            var settings = Settings()
            settings.workDuration = 1
            settings.shortBreakDuration = 1
            settings.longBreakDuration = 5
            settings.longBreakEvery = 2
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            engine.advance(by: 1)
            guard case .breaking(let first) = engine.snapshot.phase else { return fail("long-break setup") }
            engine.advance(by: 1)
            engine.advance(by: 1)
            guard case .breaking(let second) = engine.snapshot.phase else { return fail("long-break setup") }
            check("first break is short", first == .short, "kind=\(first)")
            check("second break is long", second == .long, "kind=\(second)")
            check("long break duration", engine.snapshot.total == 5, "total=\(engine.snapshot.total)")
        }

        // 3. Pause freezes the countdown and resume restores the same remaining time.
        do {
            var settings = Settings()
            settings.workDuration = 10
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            engine.advance(by: 4)
            let beforePause = engine.snapshot.remaining
            engine.pause(.detected(["Camera in use"]))
            engine.advance(by: 5)
            check("auto-pause freezes countdown", engine.snapshot.remaining == beforePause, "remaining=\(engine.snapshot.remaining)")
            check("auto-pause is reported", engine.isAutoPaused)
            engine.resume()
            check("resume restores work phase", engine.snapshot.phase == .work)
            check("resume keeps remaining", engine.snapshot.remaining == beforePause, "remaining=\(engine.snapshot.remaining)")
        }

        // 4. Postpone respects the daily snooze allowance.
        do {
            var settings = Settings()
            settings.workDuration = 10
            settings.postponeBy = 60
            settings.dailySnoozeLimitSeconds = 60
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            check("postpone accepted", engine.postpone(by: 60))
            check("postpone applied", engine.snapshot.remaining == 70, "remaining=\(engine.snapshot.remaining)")
            check("postpone blocked over quota", engine.postpone(by: 60) == false)
            check("snooze budget exhausted", engine.snapshot.remainingSnooze == 0, "left=\(engine.snapshot.remainingSnooze)")
        }

        // 5. Skip quota: the day's allowance runs out and the break can no longer be skipped.
        do {
            var settings = Settings()
            settings.workDuration = 10
            settings.shortBreakDuration = 10
            settings.dailySkipLimit = 2
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            engine.startBreakNow(.short)
            check("skip 1 allowed", engine.skipBreak())
            engine.startBreakNow(.short)
            check("skip 2 allowed", engine.skipBreak())
            engine.startBreakNow(.short)
            check("skip 3 blocked", engine.skipBreak() == false)
            check("break still running", engine.isBreaking)
            check("skip budget exhausted", engine.snapshot.remainingSkips == 0)
        }

        // 6. Pre-break reminder visibility follows the countdown.
        do {
            check("hud hidden before lead", PreBreakVisibility.shouldShow(enabled: true, isWorking: true, remaining: 120, lead: 60) == false)
            check("hud visible inside lead", PreBreakVisibility.shouldShow(enabled: true, isWorking: true, remaining: 59, lead: 60))
            check("hud hidden during break", PreBreakVisibility.shouldShow(enabled: true, isWorking: false, remaining: 30, lead: 60) == false)
            check("hud hidden when disabled", PreBreakVisibility.shouldShow(enabled: false, isWorking: true, remaining: 30, lead: 60) == false)
            check("hud hidden at zero", PreBreakVisibility.shouldShow(enabled: true, isWorking: true, remaining: 0, lead: 60) == false)
        }

        // 7. Sleep extends the running deadline instead of consuming work time.
        do {
            var settings = Settings()
            settings.workDuration = 10
            settings.pauseOnSleep = true
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            engine.advance(by: 2)
            // Real time passes while asleep, then the app compensates after wake.
            engine.advance(by: 5)
            engine.handleSystemSleep(duration: 5)
            check("sleep pauses countdown", engine.snapshot.remaining == 8, "remaining=\(engine.snapshot.remaining)")
            engine.advance(by: 2)
            check("sleep shifts deadline", engine.snapshot.remaining == 6, "remaining=\(engine.snapshot.remaining)")
        }

        // 8. A large clock jump advances through phases without hanging.
        do {
            var settings = Settings()
            settings.workDuration = 10
            settings.shortBreakDuration = 20
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            engine.advance(by: 100)
            check("clock jump enters break", engine.isBreaking, "phase=\(engine.snapshot.phase)")
        }

        // 9. Verdict debounce needs a persistent verdict before pausing.
        do {
            var debounce = VerdictDebounce()
            debounce.register(active: true)
            check("debounce: single hit does not pause", debounce.shouldPause == false)
            debounce.register(active: true)
            check("debounce: two hits pause", debounce.shouldPause)
            debounce.register(active: false)
            check("debounce: single miss does not resume", debounce.shouldResume == false)
            debounce.register(active: false)
            check("debounce: two misses resume", debounce.shouldResume)
        }

        // 10. Quota resets on the next local day.
        do {
            var now = base
            let store = QuotaStore(fileURL: tempURL("quota"), clock: { now })
            store.recordSkip()
            check("quota counted", store.remainingSkips(limit: 3) == 2, "left=\(store.remainingSkips(limit: 3))")
            now = now.addingTimeInterval(26 * 60 * 60)
            check("quota resets next day", store.remainingSkips(limit: 3) == 3, "left=\(store.remainingSkips(limit: 3))")
        }

        // 11. Settings edits reach the engine immediately through the shared store.
        do {
            let store = SettingsStore(Settings(), persists: false)
            var settings = Settings()
            settings.workDuration = 10
            settings.dailySkipLimit = 3
            settings.preBreakHUDEnabled = false
            store.setInMemory { $0 = settings }

            let engine = TimerEngine(store: store, quota: tempQuota(), clock: { base })
            check("store: initial skip budget", engine.snapshot.remainingSkips == 3, "left=\(engine.snapshot.remainingSkips)")

            store.update { $0.dailySkipLimit = 1 }
            check("store: edit applies live", engine.snapshot.remainingSkips == 1, "left=\(engine.snapshot.remainingSkips)")
        }

        // 12. Meeting matching stays conservative: browsers never match, known clients do.
        do {
            let browser = MeetingApp(name: "Chrome", bundleID: "com.google.Chrome")
            let zoom = MeetingApp(name: "Zoom", bundleID: "us.zoom.xos")
            check("meeting: browser ignored", MeetingAppMatcher.firstMatch(bundleIDs: Settings.defaultMeetingApps, running: [browser]) == nil)
            check("meeting: known client matches", MeetingAppMatcher.firstMatch(bundleIDs: Settings.defaultMeetingApps, running: [browser, zoom])?.bundleID == "us.zoom.xos")
            check("meeting: unknown client ignored", MeetingAppMatcher.firstMatch(bundleIDs: Settings.defaultMeetingApps, running: [MeetingApp(name: "OBS", bundleID: "com.obsproject.obs-studio")]) == nil)
        }

        // 13. Overlay styles resolve explicitly or rotate between breaks.
        do {
            check("style: auto starts at aurora", OverlayStyle.resolve(preference: "auto", cycleIndex: 0) == .aurora)
            check("style: auto rotates", OverlayStyle.resolve(preference: "auto", cycleIndex: 1) == .plasma)
            check("style: auto wraps", OverlayStyle.resolve(preference: "auto", cycleIndex: 3) == .aurora)
            check("style: explicit wins", OverlayStyle.resolve(preference: "rays", cycleIndex: 2) == .rays)
        }

        // 14. Every overlay shader compiles and produces a non-uniform frame.
        do {
            for style in OverlayStyle.allCases {
                guard let data = OverlayMetal.shared.renderSample(style: style) else {
                    check("metal: \(style.rawValue) renders", false, "no sample")
                    continue
                }
                let pixels = [UInt8](data)
                var lowest: UInt8 = 255
                var highest: UInt8 = 0
                for index in stride(from: 0, to: pixels.count, by: 4) {
                    let value = max(pixels[index], max(pixels[index + 1], pixels[index + 2]))
                    lowest = min(lowest, value)
                    highest = max(highest, value)
                }
                check("metal: \(style.rawValue) renders", true)
                check("metal: \(style.rawValue) not black", highest > 8, "max=\(highest)")
                check("metal: \(style.rawValue) has gradient", Int(highest) - Int(lowest) > 10, "range=\(lowest)...\(highest)")
            }
        }

        // 15. Instance lock rejects a second owner and frees itself on release.
        do {
            let path = tempURL("lock")
            defer { try? FileManager.default.removeItem(at: path) }
            let first = InstanceLock(url: path)
            let second = InstanceLock(url: path)
            check("lock: first acquire succeeds", first.acquire())
            check("lock: second acquire blocked", second.acquire() == false)
            first.release()
            check("lock: available after release", second.acquire())
            second.release()
        }

        // 16. Video and focus classifiers only match configured apps.
        do {
            check("video: player matches", VideoClassifier.isPlayer(bundleID: "com.colliderli.iina", allowlist: Settings.defaultVideoPlayers))
            check("video: non-player skipped", VideoClassifier.isPlayer(bundleID: "com.apple.dt.Xcode", allowlist: Settings.defaultVideoPlayers) == false)
            check("video: unknown owner skipped", VideoClassifier.isPlayer(bundleID: nil, allowlist: Settings.defaultVideoPlayers) == false)
            check("focus: frontmost matches", FocusMatcher.matches(frontmost: "com.apple.dt.Xcode", focusApps: ["com.apple.dt.Xcode"]))
            check("focus: other app skipped", FocusMatcher.matches(frontmost: "com.apple.Safari", focusApps: ["com.apple.dt.Xcode"]) == false)
        }

        // 17. Office hours handle in-window, out-of-window, weekday and overnight cases.
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
            let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 20))!
            let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 23))!
            let weekday = calendar.component(.weekday, from: noon)

            check("office hours: inside window", OfficeHours.isActive(date: noon, startHour: 9, endHour: 18, weekdays: [weekday], calendar: calendar))
            check("office hours: outside window", OfficeHours.isActive(date: evening, startHour: 9, endHour: 18, weekdays: [weekday], calendar: calendar) == false)
            check("office hours: weekday excluded", OfficeHours.isActive(date: noon, startHour: 9, endHour: 18, weekdays: [], calendar: calendar) == false)
            check("office hours: overnight inside", OfficeHours.isActive(date: night, startHour: 22, endHour: 6, weekdays: [weekday], calendar: calendar))
            check("office hours: overnight outside", OfficeHours.isActive(date: noon, startHour: 22, endHour: 6, weekdays: [weekday], calendar: calendar) == false)
        }

        // 18. Stats store records intervals and summarises the current day.
        do {
            let url = tempURL("stats")
            let store = StatsStore(fileURL: url)
            let now = Date()
            store.append(StatsRecord(kind: .work, start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300)))
            store.append(StatsRecord(kind: .shortBreak, start: now.addingTimeInterval(-300), end: now.addingTimeInterval(-280)))

            let reloaded = StatsStore(fileURL: url)
            let summary = reloaded.summary(for: now)
            check("stats persisted", reloaded.records.count == 2, "count=\(reloaded.records.count)")
            check("stats work total", abs(summary.workSeconds - 300) < 1, "work=\(summary.workSeconds)")
            check("stats break count", summary.breakCount == 1, "breaks=\(summary.breakCount)")
            check("stats summary text", summary.text.contains("5m"), summary.text)
        }

        // 19. The overlay skip button unlocks only after the minimum break time
        //     and only while the day's skip quota remains.
        do {
            check("skip gate: locked before 10s", OverlaySkipGate.shouldShow(elapsed: 9.5, remainingSkips: 3) == false)
            check("skip gate: unlocked at 10s", OverlaySkipGate.shouldShow(elapsed: 10, remainingSkips: 3))
            check("skip gate: hidden once quota exhausted", OverlaySkipGate.shouldShow(elapsed: 30, remainingSkips: 0) == false)

            let model = OverlayModel()
            model.total = 20
            model.remaining = 12
            model.remainingSkips = 2
            check("overlay elapsed derived from countdown", model.elapsed == 8, "elapsed=\(model.elapsed)")
            check("overlay hides skip at 8s", model.showsSkip == false)
            model.remaining = 10
            check("overlay shows skip at 10s", model.showsSkip)
        }

        // 20. Long breaks lock the screen once, after the skip button has had time to be used.
        do {
            var gate = BreakLockGate()
            let delay = BreakLockGate.lockDelay
            check("lock gate: skip window opens before the lock", OverlaySkipGate.unlockDelay < delay)
            check("lock gate: quiet before the grace ends", gate.shouldLockScreen(kind: .long, enabled: true, elapsed: delay - 0.1) == false)
            check("lock gate: fires once the grace ends", gate.shouldLockScreen(kind: .long, enabled: true, elapsed: delay))
            check("lock gate: fires once per break", gate.shouldLockScreen(kind: .long, enabled: true, elapsed: 300) == false)

            gate.reset()
            check("lock gate: short breaks never lock", gate.shouldLockScreen(kind: .short, enabled: true, elapsed: 300) == false)
            check("lock gate: disabled stays quiet", gate.shouldLockScreen(kind: .long, enabled: false, elapsed: 300) == false)
            check("lock gate: fires after reset", gate.shouldLockScreen(kind: .long, enabled: true, elapsed: delay + 1))
        }

        // 21. Settings survive a JSON round trip, so a new key cannot silently
        //     fall back to its default for existing users.
        do {
            var settings = Settings()
            settings.lockScreenDuringLongBreak = false
            settings.dailySkipLimit = 7
            guard let data = try? JSONEncoder().encode(settings),
                  let decoded = try? JSONDecoder().decode(Settings.self, from: data)
            else { return fail("settings round trip") }
            check("settings keep lock-screen flag", decoded.lockScreenDuringLongBreak == false)
            check("settings keep skip limit", decoded.dailySkipLimit == 7, "limit=\(decoded.dailySkipLimit)")
            check("settings round trip is lossless", decoded == settings)
        }

        // 22. Driven through the real engine, only the long break trips the lock,
        //     and it does so exactly once while the break is still running.
        do {
            var settings = Settings()
            settings.workDuration = 3
            settings.shortBreakDuration = 20
            settings.longBreakDuration = 60
            settings.longBreakEvery = 2
            settings.preBreakHUDEnabled = false
            let engine = TimerEngine(settings: settings, quota: tempQuota(), clock: { base })

            var gate = BreakLockGate()
            var locks = 0
            var sawShortBreak = false
            engine.onChange = { snapshot in
                guard snapshot.isBreaking else { return }
                let kind: BreakKind = snapshot.total == 60 ? .long : .short
                if kind == .short { sawShortBreak = true }
                let elapsed = snapshot.total - snapshot.remaining
                if gate.shouldLockScreen(kind: kind, enabled: true, elapsed: elapsed) {
                    locks += 1
                }
            }

            for _ in 0..<23 { engine.advance(by: 1) }   // work 3 + short break 20
            check("lock wiring: short break observed", sawShortBreak)
            check("lock wiring: short break never locks", locks == 0, "locks=\(locks)")

            for _ in 0..<28 { engine.advance(by: 1) }   // work 3 + long break 25
            check("lock wiring: long break locks once", locks == 1, "locks=\(locks)")
            check("lock wiring: break still running", engine.isBreaking)
        }

        print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
        return Int32(failures)
    }

    // MARK: - Helpers

    @MainActor
    private static func tempQuota() -> QuotaStore {
        QuotaStore(fileURL: tempURL("quota"))
    }

    private static func tempURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stepaway-selftest-\(label)-\(UUID().uuidString).json")
    }

    private static func fail(_ name: String) -> Int32 {
        print("FAIL  \(name)")
        return 1
    }
}
