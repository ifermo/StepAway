import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let engine: TimerEngine
    private let onPreviewSound: (String) -> Void
    private var window: NSWindow?

    init(store: SettingsStore, engine: TimerEngine, onPreviewSound: @escaping (String) -> Void) {
        self.store = store
        self.engine = engine
        self.onPreviewSound = onPreviewSound
    }

    func show() {
        if window == nil {
            let view = SettingsView(store: store, engine: engine, onPreviewSound: onPreviewSound)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "StepAway 设置"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let engine: TimerEngine
    let onPreviewSound: (String) -> Void

    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static let weekdayNames: [Int: String] = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]

    private let soundNames = [
        "Glass", "Ping", "Pop", "Purr", "Submarine",
        "Blow", "Bottle", "Frog", "Funk", "Hero", "Morse", "Sosumi", "Tink"
    ]

    var body: some View {
        ScrollView {
            Form {
                timingSection
                appearanceSection
                reminderSection
                soundSection
                quotaSection
                detectorSection
                focusSection
                officeHoursSection
                ignoreSection
                resetSection
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Sections

    private var timingSection: some View {
        Section("计时") {
            Stepper("工作：\(minutes(store.value.workDuration)) 分钟",
                    value: durationBinding(\.workDuration), in: 60...7200, step: 60)
            Stepper("短休息：\(seconds(store.value.shortBreakDuration)) 秒",
                    value: durationBinding(\.shortBreakDuration), in: 5...600, step: 5)
            Stepper("长休息：\(minutes(store.value.longBreakDuration)) 分钟",
                    value: durationBinding(\.longBreakDuration), in: 60...3600, step: 60)
            Stepper("每 \(store.value.longBreakEvery) 次短休息后长休息",
                    value: intBinding(\.longBreakEvery), in: 1...10)
            Text("改动在当前计时结束后生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        Section("休息动效") {
            Picker("动效", selection: stringBinding(\.overlayStyle)) {
                Text("自动轮换").tag("auto")
                ForEach(OverlayStyle.allCases, id: \.rawValue) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            Text("动效由 Metal 着色器实时渲染；显卡不可用时回退到渐变。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var reminderSection: some View {
        Section("打断前提醒") {
            Toggle("休息前显示提醒浮窗", isOn: boolBinding(\.preBreakHUDEnabled))
            Stepper("提前：\(seconds(store.value.preBreakLeadSeconds)) 秒",
                    value: durationBinding(\.preBreakLeadSeconds), in: 10...300, step: 10)
        }
    }

    private var soundSection: some View {
        Section("声音") {
            Toggle("启用声音", isOn: boolBinding(\.soundEnabled))
            HStack {
                Text("音量")
                Slider(value: volumeBinding(), in: 0...1)
                Text("\(Int(store.value.soundVolume * 100))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            HStack {
                Picker("开始音", selection: stringBinding(\.soundStartName)) {
                    ForEach(soundNames, id: \.self) { Text($0) }
                }
                Picker("结束音", selection: stringBinding(\.soundEndName)) {
                    ForEach(soundNames, id: \.self) { Text($0) }
                }
            }
            HStack {
                Button("试听开始音") { onPreviewSound(store.value.soundStartName) }
                Button("试听结束音") { onPreviewSound(store.value.soundEndName) }
            }
        }
    }

    private var quotaSection: some View {
        Section("每日配额") {
            Stepper("可跳过休息：\(store.value.dailySkipLimit) 次",
                    value: intBinding(\.dailySkipLimit), in: 0...20)
            Stepper("可推迟累计：\(minutes(store.value.dailySnoozeLimitSeconds)) 分钟",
                    value: durationBinding(\.dailySnoozeLimitSeconds), in: 0...7200, step: 300)
            Text("重置于本地时间每天 0 点；当前已用额度见菜单栏。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detectorSection: some View {
        Section("自动暂停") {
            Toggle("视频播放（全屏 + 播放器）", isOn: boolBinding(\.videoDetectorEnabled))
            Toggle("全屏应用（游戏等）", isOn: boolBinding(\.fullscreenDetectorEnabled))
            Toggle("忽略当前正在使用的全屏应用", isOn: boolBinding(\.excludeFrontmostApp))
            Toggle("日历事件期间暂停", isOn: boolBinding(\.calendarDetectorEnabled))
            Toggle("会议/屏幕共享期间暂停（麦克风或摄像头占用 + 会议应用运行）", isOn: boolBinding(\.screenSharingDetectorEnabled))
            if MediaDeviceProbe.deviceCount == 0 {
                Text("本机没有摄像头或麦克风，媒体占用信号不可用，会议检测不会触发。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("系统休眠期间暂停计时", isOn: boolBinding(\.pauseOnSleep))
        }
    }

    private var focusSection: some View {
        Section("专注应用") {
            Toggle("在前台使用专注应用时不打断", isOn: boolBinding(\.deepFocusDetectorEnabled))
            if store.value.focusAppBundleIDs.isEmpty {
                Text("暂无。打开目标应用后，用菜单栏「标记当前应用为专注应用」添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.value.focusAppBundleIDs, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName(for: bundleID))
                            Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("移除") {
                            store.update { $0.focusAppBundleIDs.removeAll { $0 == bundleID } }
                        }
                    }
                }
            }
        }
    }

    private var officeHoursSection: some View {
        Section("办公时间") {
            Toggle("仅在工作时间内计时", isOn: boolBinding(\.officeHoursEnabled))
            Stepper("开始：\(store.value.officeStartHour):00", value: intBinding(\.officeStartHour), in: 0...23)
            Stepper("结束：\(store.value.officeEndHour):00", value: intBinding(\.officeEndHour), in: 0...23)
            HStack(spacing: 10) {
                ForEach(SettingsView.weekdayOrder, id: \.self) { day in
                    Toggle(SettingsView.weekdayNames[day] ?? "", isOn: weekdayBinding(day))
                        .toggleStyle(.checkbox)
                }
            }
            Text("结束时间早于开始时间时按跨午夜处理；关闭开关则整天计时。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var ignoreSection: some View {
        Section("忽略名单") {
            if store.value.ignoredBundleIDs.isEmpty {
                Text("暂无。在全屏应用激活时，用菜单栏「忽略当前应用」添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.value.ignoredBundleIDs, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName(for: bundleID))
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("移除") {
                            store.update { $0.ignoredBundleIDs.removeAll { $0 == bundleID } }
                        }
                    }
                }
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("恢复默认设置", role: .destructive) {
                store.update { $0 = Settings() }
            }
        }
    }

    // MARK: - Bindings

    private func durationBinding(_ keyPath: WritableKeyPath<Settings, TimeInterval>) -> Binding<Double> {
        Binding(
            get: { store.value[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<Settings, Int>) -> Binding<Int> {
        Binding(
            get: { store.value[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.value[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<Settings, String>) -> Binding<String> {
        Binding(
            get: { store.value[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { store.value.officeWeekdays.contains(weekday) },
            set: { isOn in
                store.update { settings in
                    if isOn {
                        if !settings.officeWeekdays.contains(weekday) {
                            settings.officeWeekdays.append(weekday)
                            settings.officeWeekdays.sort()
                        }
                    } else {
                        settings.officeWeekdays.removeAll { $0 == weekday }
                    }
                }
            }
        )
    }

    private func volumeBinding() -> Binding<Double> {
        Binding(
            get: { store.value.soundVolume },
            set: { newValue in store.update { $0.soundVolume = newValue } }
        )
    }

    // MARK: - Formatting

    private func minutes(_ duration: TimeInterval) -> Int {
        Int((duration / 60).rounded())
    }

    private func seconds(_ duration: TimeInterval) -> Int {
        Int(duration.rounded())
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }
}
