import AppKit

/// Pure decision so the show/hide rule is testable without AppKit.
enum PreBreakVisibility {
    static func shouldShow(enabled: Bool, isWorking: Bool, remaining: TimeInterval, lead: TimeInterval) -> Bool {
        enabled && isWorking && remaining > 0 && remaining <= lead
    }
}

/// Non-activating floating reminder shown shortly before a break starts, so the
/// user is not dropped into a fullscreen overlay without warning.
@MainActor
final class PreBreakHUD {
    private let onPostpone: () -> Void
    private var panel: NSPanel?
    private var label: NSTextField?

    init(onPostpone: @escaping () -> Void) {
        self.onPostpone = onPostpone
    }

    /// Called on every engine tick: the reminder must count down with the timer,
    /// not freeze at the value it was first shown with.
    func sync(enabled: Bool, isWorking: Bool, remaining: TimeInterval, lead: TimeInterval) {
        guard PreBreakVisibility.shouldShow(enabled: enabled, isWorking: isWorking, remaining: remaining, lead: lead) else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        label?.stringValue = "还有 \(formatted(remaining)) 开始休息"
        position(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    @objc private func postpone() {
        onPostpone()
        hide()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let effect = NSVisualEffectView(frame: panel.contentLayoutRect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .labelColor
        label = title

        let postponeButton = NSButton(title: "推迟 5 分钟", target: self, action: #selector(postpone))
        postponeButton.bezelStyle = .rounded
        postponeButton.controlSize = .small

        let stack = NSStackView(views: [title, postponeButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14)
        ])

        panel.contentView = effect
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - 24,
            y: frame.minY + 24
        ))
    }

    private func formatted(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
