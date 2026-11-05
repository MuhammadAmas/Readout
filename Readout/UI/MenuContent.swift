import KeyboardShortcuts
import ReadoutCore
import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var queue: ReadingQueue

    var body: some View {
        switch queue.state {
        case .idle: Image(systemName: "text.bubble")
        case .speaking: Image(systemName: "text.bubble.fill")
        case .paused: Image(systemName: "pause.bubble")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var queue: ReadingQueue

    var body: some View {
        Button("Read Selection") { model.readSelectionFromMenu() }
            .shortcut(for: .readSelection)
            .disabled(queue.isActive)

        Button(queue.state == .paused ? "Resume" : "Pause") { model.togglePause() }
            .shortcut(for: .pauseResume)
            .disabled(!queue.isActive)

        Button("Stop") { model.stop() }
            .disabled(!queue.isActive)

        Button("Show Mini Player") { model.showMiniPlayer() }
            .disabled(!queue.isActive)

        Divider()

        if !model.isTrusted {
            Button("Allow Accessibility Access…") { model.showOnboarding() }
            Divider()
        }

        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("About Readout") { model.showAbout() }

        Divider()

        Button("Quit Readout") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private extension View {
    @ViewBuilder
    func shortcut(for name: KeyboardShortcuts.Name) -> some View {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name),
           let character = shortcut.description.last,
           character.isLetter || character.isNumber {
            keyboardShortcut(
                KeyEquivalent(Character(character.lowercased())),
                modifiers: EventModifiers(shortcut.modifiers)
            )
        } else {
            self
        }
    }
}

private extension EventModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
