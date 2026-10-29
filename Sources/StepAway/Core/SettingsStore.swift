import Foundation

/// Single source of truth for settings. Everything that reads tunables at runtime
/// (engine limits, detectors, menu, sound) holds this store instead of a copy, so
/// edits from the settings window apply without a restart.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var value: Settings
    private let persists: Bool

    init(_ value: Settings = .load(), persists: Bool = true) {
        self.value = value
        self.persists = persists
    }

    func update(_ mutate: (inout Settings) -> Void) {
        mutate(&value)
        if persists { value.save() }
    }

    /// Used by `--demo` so short-cycle values never reach UserDefaults.
    func setInMemory(_ mutate: (inout Settings) -> Void) {
        mutate(&value)
    }

    func isIgnoring(bundleID: String) -> Bool {
        value.ignoredBundleIDs.contains(bundleID)
    }

    func toggleIgnore(bundleID: String) {
        if let index = value.ignoredBundleIDs.firstIndex(of: bundleID) {
            value.ignoredBundleIDs.remove(at: index)
        } else {
            value.ignoredBundleIDs.append(bundleID)
        }
        value.save()
    }
}
