import AppKit
import SwiftUI

/// Pure decision so the skip rule is testable without AppKit.
enum OverlaySkipGate {
    /// Every break is served in full for at least this long before the user is
    /// offered a way out.
    static let unlockDelay: TimeInterval = 10

    static func shouldShow(
        elapsed: TimeInterval,
        remainingSkips: Int,
        unlockDelay: TimeInterval = OverlaySkipGate.unlockDelay
    ) -> Bool {
        remainingSkips > 0 && elapsed >= unlockDelay
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var remaining: TimeInterval = 0
    @Published var total: TimeInterval = 1
    @Published var style: OverlayStyle = .aurora
    @Published var remainingSkips: Int = 0

    var clock: String {
        let value = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    var elapsed: TimeInterval { max(0, total - remaining) }

    var showsSkip: Bool {
        OverlaySkipGate.shouldShow(elapsed: elapsed, remainingSkips: remainingSkips)
    }
}

struct BreakOverlayView: View {
    @ObservedObject var model: OverlayModel
    var onSkip: () -> Void = {}

    var body: some View {
        ZStack {
            if OverlayMetal.shared.isAvailable {
                MetalOverlayBackground(style: model.style, progress: model.progress)
                    .ignoresSafeArea()
            } else {
                GradientFallback()
            }

            VStack(spacing: 18) {
                Text(model.kind.title)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .opacity(0.75)
                Text("看向 6 米外，放松眼部")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .opacity(0.6)
                Text(model.clock)
                    .font(.system(size: 92, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(.white)

            // Bottom-anchored so the countdown does not shift when the button appears.
            VStack {
                Spacer()
                if model.showsSkip {
                    SkipButton(remainingSkips: model.remainingSkips, action: onSkip)
                        .padding(.bottom, 64)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.showsSkip)
    }
}

private struct SkipButton: View {
    let remainingSkips: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("跳过休息（今日剩余 \(remainingSkips) 次）")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.white.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.88))
    }
}

private struct GradientFallback: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            AngularGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.22),
                    Color(red: 0.16, green: 0.28, blue: 0.42),
                    Color(red: 0.09, green: 0.12, blue: 0.20)
                ],
                center: .center,
                angle: .degrees(phase * 4)
            )
            .blur(radius: 40)
            .ignoresSafeArea()
        }
    }
}

@MainActor
final class OverlayWindow: NSWindow {
    init(screen: NSScreen, hidesFromScreenCapture: Bool) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above fullscreen apps and every Space; needs .fullScreenAuxiliary to join
        // another app's fullscreen Space instead of pulling the user out of it.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if hidesFromScreenCapture {
            sharingType = .none
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The overlay never becomes key, so AppKit would otherwise eat the first click
/// on the skip button as a window-activation click.
@MainActor
final class OverlayHostingView: NSHostingView<BreakOverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class BreakOverlayController {
    private let store: SettingsStore
    private let model = OverlayModel()
    private let onSkip: () -> Void
    private var windows: [OverlayWindow] = []

    init(store: SettingsStore, onSkip: @escaping () -> Void) {
        self.store = store
        self.onSkip = onSkip
    }

    func show(
        kind: BreakKind,
        remaining: TimeInterval,
        total: TimeInterval,
        style: OverlayStyle,
        remainingSkips: Int
    ) {
        model.kind = kind
        model.remaining = remaining
        model.total = max(total, 1)
        model.style = style
        model.remainingSkips = remainingSkips
        if windows.isEmpty {
            // Opt-out only for local verification captures.
            let hide = store.value.hideOverlayFromScreenCapture
                && ProcessInfo.processInfo.environment["STEPAWAY_SHOW_IN_CAPTURE"] == nil
            for screen in NSScreen.screens {
                let window = OverlayWindow(screen: screen, hidesFromScreenCapture: hide)
                window.contentView = OverlayHostingView(
                    rootView: BreakOverlayView(model: model, onSkip: onSkip)
                )
                window.setFrame(screen.frame, display: true)
                window.orderFrontRegardless()
                windows.append(window)
            }
        }
    }

    func hide() {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
