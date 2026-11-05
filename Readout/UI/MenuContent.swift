import KeyboardShortcuts
import ReadoutCore
import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var queue: ReadingQueue

    var body: some View {
        switch queue.state {
        case .idle: Image(systemName: "text.bubble")
        case .speaking: Image(systemName: "speaker.wave.2.bubble.fill")
        case .paused: Image(systemName: "pause.bubble")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var queue: ReadingQueue

    var body: some View {
        if queue.isActive {
            Button(queue.state == .paused ? "Resume" : "Pause") { model.togglePause() }
            Button("Stop Reading") { model.stop() }
            if let sentence = queue.currentSentence {
                Text("Reading \(queue.currentIndex + 1) of \(queue.sentences.count): \(sentence.prefix(40))…")
            }
        } else {
            Button("Read Selection   \(Hotkeys.label(for: .readSelection))") {
                model.readSelectionFromMenu()
            }
        }

        Divider()

        if !model.isTrusted {
            Button("Grant Accessibility Access…") { model.showOnboarding() }
            Divider()
        }

        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")

        Button("Quit Readout") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
