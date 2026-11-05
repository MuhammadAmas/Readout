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
        let panel = FloatingPanel(size: hosting.fittingSize, interactive: true)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        if !panel.setFrameUsingName(Self.autosaveName) {
            placeAtDefaultPosition(panel)
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        return panel
    }

    private func placeAtDefaultPosition(_ panel: NSPanel) {
        guard let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 20, y: frame.minY + 20))
    }
}

struct MiniPlayerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var queue: ReadingQueue
    @AppStorage(Preferences.speechRate) private var rate = Preferences.Defaults.speechRate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(highlightedSentence)
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .lineLimit(5)
                .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
                .textSelection(.disabled)
                .accessibilityLabel(queue.currentSentence ?? "")
            controls
        }
        .padding(14)
        .frame(width: 380)
        .background(WindowDragArea())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
        .padding(10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: queue.state == .paused ? "pause.circle.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.tint)
            Text(progress)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: model.hideMiniPlayer) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide the player. Reading continues.")
            .accessibilityLabel("Hide player")
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            control("backward.fill", label: "Previous sentence", disabled: queue.currentIndex == 0) {
                model.skip(by: -1)
            }
            control(queue.state == .paused ? "play.fill" : "pause.fill", label: queue.state == .paused ? "Resume" : "Pause", prominent: true) {
                model.togglePause()
            }
            control("stop.fill", label: "Stop") {
                model.stop()
            }
            control("forward.fill", label: "Next sentence") {
                model.skip(by: 1)
            }
            Spacer()
            Menu {
                ForEach(Preferences.rateSteps, id: \.self) { step in
                    Button {
                        model.setRate(step)
                    } label: {
                        if abs(step - rate) < 0.01 {
                            Label(Preferences.formatted(rate: step), systemImage: "checkmark")
                        } else {
                            Text(Preferences.formatted(rate: step))
                        }
                    }
                }
            } label: {
                Text(Preferences.formatted(rate: rate))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Speaking speed")
        }
    }

    private func control(
        _ symbol: String,
        label: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 14, weight: .semibold))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(label)
        .accessibilityLabel(label)
    }

    private var progress: String {
        guard !queue.sentences.isEmpty else { return "Readout" }
        return "Sentence \(queue.currentIndex + 1) of \(queue.sentences.count)"
    }

    private var highlightedSentence: AttributedString {
        guard let sentence = queue.currentSentence else { return AttributedString("") }
        var attributed = AttributedString(sentence)
        guard let range = queue.spokenRange,
              let stringRange = Range(range, in: sentence),
              let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
        else { return attributed }
        attributed[attributed.startIndex..<lower].foregroundColor = .secondary
        attributed[lower..<upper].backgroundColor = Color.accentColor.opacity(0.28)
        return attributed
    }
}
