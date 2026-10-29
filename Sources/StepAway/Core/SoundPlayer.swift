import AppKit

@MainActor
final class SoundPlayer {
    private let store: SettingsStore
    private var active: NSSound?

    init(store: SettingsStore) {
        self.store = store
    }

    func playStart() {
        play(named: store.value.soundStartName)
    }

    func playEnd() {
        play(named: store.value.soundEndName)
    }

    /// Used by the settings window to audition a system sound.
    func preview(_ name: String) {
        play(named: name, force: true)
    }

    private func play(named name: String, force: Bool = false) {
        let settings = store.value
        guard force || settings.soundEnabled, let sound = NSSound(named: NSSound.Name(name)) else { return }
        active?.stop()
        sound.volume = Float(min(max(settings.soundVolume, 0), 1))
        sound.play()
        active = sound
    }
}
