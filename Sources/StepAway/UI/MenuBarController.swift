import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let engine: TimerEngine
    private let store: SettingsStore
    private let summaryProvider: () -> StatsStore.Summary
    private let currentAppBundleID: () -> String?
    private let onOpenSettings: () -> Void

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let summaryItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let ignoreItem = NSMenuItem(title: "忽略当前应用", action: #selector(toggleIgnore), keyEquivalent: "")
    private let focusItem = NSMenuItem(title: "标记当前应用为专注应用", action: #selector(toggleFocusApp), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
    private let startBreakItem = NSMenuItem(title: "Start break now", action: #selector(startBreak), keyEquivalent: "b")
    private let skipBreakItem = NSMenuItem(title: "Skip break", action: #selector(skipBreak), keyEquivalent: "s")
    private let postponeItem = NSMenuItem(title: "Postpone", action: #selector(postpone), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")

    init(
        engine: TimerEngine,
        store: SettingsStore,
        summaryProvider: @escaping () -> StatsStore.Summary,
        currentAppBundleID: @escaping () -> String?,
        onOpenSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.store = store
        self.summaryProvider = summaryProvider
        self.currentAppBundleID = currentAppBundleID
        self.onOpenSettings = onOpenSettings
        super.init()

        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        buildMenu()
        statusItem.menu = menu
        render(engine.snapshot)
    }

    private func buildMenu() {
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())

        ignoreItem.target = self
        menu.addItem(ignoreItem)
        focusItem.target = self
        focusItem.isHidden = true
        menu.addItem(focusItem)
        for item in [pauseItem, startBreakItem, skipBreakItem, postponeItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func render(_ snapshot: TimerEngine.Snapshot) {
        let settings = store.value
        statusItem.button?.title = statusText(for: snapshot)
        pauseItem.title = pauseTitle(for: snapshot)
        startBreakItem.isEnabled = !snapshot.isBreaking

        skipBreakItem.isEnabled = snapshot.isBreaking && snapshot.remainingSkips > 0
        skipBreakItem.title = "Skip break (\(snapshot.remainingSkips) left)"

        postponeItem.isEnabled = snapshot.phase == .work
            && snapshot.remainingSnooze >= settings.postponeBy
        postponeItem.title = "Postpone \(Int(settings.postponeBy / 60)) min (\(snoozeText(snapshot.remainingSnooze)) left)"

        summaryItem.title = summaryProvider().text
        ignoreItem.title = ignoreTitle()
        ignoreItem.isEnabled = currentAppBundleID() != nil

        focusItem.isHidden = !store.value.deepFocusDetectorEnabled
        focusItem.title = focusTitle()
        focusItem.isEnabled = currentAppBundleID() != nil
    }

    private func statusText(for snapshot: TimerEngine.Snapshot) -> String {
        switch snapshot.phase {
        case .work:
            return snapshot.clock
        case .breaking:
            return "☕ " + snapshot.clock
        case .paused(let reason):
            switch reason {
            case .manual:
                return "⏸ " + snapshot.clock
            case .detected:
                return "◐ " + snapshot.clock
            }
        case .stopped:
            return "—"
        }
    }

    private func pauseTitle(for snapshot: TimerEngine.Snapshot) -> String {
        switch snapshot.phase {
        case .paused(let reason):
            return "Resume (\(reason.label))"
        default:
            return "Pause"
        }
    }

    private func snoozeText(_ remaining: TimeInterval) -> String {
        "\(max(0, Int(remaining / 60)))m"
    }

    private func focusTitle() -> String {
        guard let bundleID = currentAppBundleID() else { return "标记当前应用为专注应用" }
        return store.value.focusAppBundleIDs.contains(bundleID) ? "取消专注应用标记" : "标记当前应用为专注应用"
    }

    private func ignoreTitle() -> String {
        guard let bundleID = currentAppBundleID() else { return "忽略当前应用" }
        return store.isIgnoring(bundleID: bundleID) ? "取消忽略当前应用" : "忽略当前应用"
    }

    // MARK: - Actions

    @objc private func toggleIgnore() {
        guard let bundleID = currentAppBundleID() else { return }
        store.toggleIgnore(bundleID: bundleID)
        render(engine.snapshot)
    }

    @objc private func toggleFocusApp() {
        guard let bundleID = currentAppBundleID() else { return }
        store.update { settings in
            if let index = settings.focusAppBundleIDs.firstIndex(of: bundleID) {
                settings.focusAppBundleIDs.remove(at: index)
            } else {
                settings.focusAppBundleIDs.append(bundleID)
            }
        }
        render(engine.snapshot)
    }

    @objc private func togglePause() {
        if case .paused(_) = engine.snapshot.phase {
            engine.resume()
        } else {
            engine.pause(.manual)
        }
    }

    @objc private func startBreak() {
        engine.startBreakNow(.short)
    }

    @objc private func skipBreak() {
        engine.skipBreak()
        render(engine.snapshot)
    }

    @objc private func postpone() {
        engine.postpone(by: store.value.postponeBy)
        render(engine.snapshot)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
