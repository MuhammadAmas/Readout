import AppKit
import ReadoutCore
import SwiftUI

@MainActor
final class MiniPlayerController {
    private static let autosaveName = "ReadoutMiniPlayer"

    private unowned let model: AppModel
    private var panel: FloatingPanel?

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            placeAtDefaultPosition(panel)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let hosting = NSHostingView(rootView: MiniPlayerView(model: model, queue: model.queue))
        let size = hosting.fittingSize
        let panel = FloatingPanel(size: size, interactive: true)
        panel.contentView = hosting
        if panel.setFrameUsingName(Self.autosaveName) {
            let origin = panel.frame.origin
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        } else {
            panel.setContentSize(size)
            placeAtDefaultPosition(panel)
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        return panel
    }

    private func placeAtDefaultPosition(_ panel: NSPanel) {
        guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 12, y: frame.minY + 12))
    }
}

struct MiniPlayerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var queue: ReadingQueue
    @AppStorage(Preferences.speechRate) private var rate = Preferences.Defaults.speechRate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ReadingLine(sentence: queue.currentSentence ?? "", spoken: queue.spokenRange)
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
            ProgressTrack(
                position: position,
                count: queue.sentences.count,
                current: queue.currentIndex,
                jump: model.jump(to:)
            )
            controls
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(width: 400)
        .background(WindowDragArea())
        .floatingSurface(cornerRadius: 22)
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label {
                Text(queue.state == .paused ? "Paused" : "Reading")
                    .font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: queue.state == .paused ? "pause.fill" : "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: queue.state == .speaking)
            }
            if let voice = voiceName {
                Text(voice)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(counter)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(action: model.hideMiniPlayer) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(PlayerButtonStyle(size: 24))
            .help("Hide the player. Reading continues; show it again from the menu bar.")
            .accessibilityLabel("Hide player")
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { model.skip(by: -1) } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(PlayerButtonStyle())
            .disabled(queue.currentIndex == 0)
            .help("Previous sentence")
            .accessibilityLabel("Previous sentence")

            Button(action: model.togglePause) {
                Image(systemName: queue.state == .paused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PlayerButtonStyle(size: 42, prominent: true))
            .help(queue.state == .paused ? "Resume (\(Hotkeys.label(for: .pauseResume)))" : "Pause (\(Hotkeys.label(for: .pauseResume)))")
            .accessibilityLabel(queue.state == .paused ? "Resume" : "Pause")

            Button { model.skip(by: 1) } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(PlayerButtonStyle())
            .help("Next sentence")
            .accessibilityLabel("Next sentence")

            Button(action: model.stop) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(PlayerButtonStyle())
            .help("Stop (\(Hotkeys.label(for: .readSelection)))")
            .accessibilityLabel("Stop")

            Spacer()

            Menu {
                Picker("Speed", selection: Binding(get: { rate }, set: model.setRate)) {
                    ForEach(Preferences.rateSteps, id: \.self) { step in
                        Text(Preferences.formatted(rate: step)).tag(step)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(Preferences.formatted(rate: rate), systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .fixedSize()
            .help("Speaking speed")
            .accessibilityLabel("Speed \(Preferences.formatted(rate: rate))")
        }
    }

    private var voiceName: String? {
        guard let identifier = queue.currentSettings.voiceIdentifier,
              let option = VoiceCatalog.option(identifier: identifier)
        else { return nil }
        return option.isNeural ? "\(option.name) · Neural" : option.name
    }

    private var counter: String {
        guard !queue.sentences.isEmpty else { return "" }
        return "\(queue.currentIndex + 1) of \(queue.sentences.count)"
    }

    private var position: Double {
        guard !queue.sentences.isEmpty else { return 0 }
        var within = 0.0
        if let sentence = queue.currentSentence, let range = queue.spokenRange {
            let length = max((sentence as NSString).length, 1)
            within = Double(range.location + range.length) / Double(length)
        }
        return (Double(queue.currentIndex) + min(within, 1)) / Double(queue.sentences.count)
    }
}

private struct ReadingLine: View {
    let sentence: String
    let spoken: NSRange?

    var body: some View {
        Text(attributed)
            .font(.system(size: 15, weight: .regular))
            .lineSpacing(3)
            .lineLimit(4)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .accessibilityLabel(sentence)
    }

    private var attributed: AttributedString {
        var text = AttributedString(sentence)
        text.foregroundColor = .secondary
        guard let spoken,
              let stringRange = Range(spoken, in: sentence),
              let lower = AttributedString.Index(stringRange.lowerBound, within: text),
              let upper = AttributedString.Index(stringRange.upperBound, within: text)
        else { return text }
        text[text.startIndex..<upper].foregroundColor = .primary
        text[lower..<upper].backgroundColor = Color.accentColor.opacity(0.3)
        return text
    }
}

private struct ProgressTrack: View {
    let position: Double
    let count: Int
    let current: Int
    let jump: (Int) -> Void

    @State private var hoverFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(.tint).frame(width: max(4, width * position))
                if let hoverFraction {
                    Capsule()
                        .fill(.primary.opacity(0.5))
                        .frame(width: 2, height: 10)
                        .offset(x: width * hoverFraction - 1)
                }
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverFraction = min(max(location.x / width, 0), 1)
                case .ended: hoverFraction = nil
                }
            }
            .onTapGesture { location in
                guard count > 0 else { return }
                jump(min(count - 1, max(0, Int(location.x / width * Double(count)))))
            }
        }
        .frame(height: 14)
        .help("Click to jump to another sentence")
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue("Sentence \(current + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: jump(min(count - 1, current + 1))
            case .decrement: jump(max(0, current - 1))
            @unknown default: break
            }
        }
    }
}

struct PlayerButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PlayerButtonBody(configuration: configuration, size: size, prominent: prominent)
    }
}

private struct PlayerButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let size: CGFloat
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: prominent ? 17 : 13, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: size, height: size)
            .background {
                Circle().fill(fill)
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }

    private var fill: AnyShapeStyle {
        if prominent {
            return AnyShapeStyle(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
        }
        return AnyShapeStyle(Color.primary.opacity(isHovering && isEnabled ? 0.1 : 0))
    }
}
