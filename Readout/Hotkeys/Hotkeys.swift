import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let readSelection = Self("readSelection", default: .init(.r, modifiers: [.control, .option]))
    static let pauseResume = Self("pauseResume", default: .init(.p, modifiers: [.control, .option]))
}

@MainActor
enum Hotkeys {
    static func register(model: AppModel) {
        KeyboardShortcuts.onKeyDown(for: .readSelection) {
            MainActor.assumeIsolated { model.toggleReading() }
        }
        KeyboardShortcuts.onKeyDown(for: .pauseResume) {
            MainActor.assumeIsolated { model.togglePause() }
        }
    }

    static func label(for name: KeyboardShortcuts.Name) -> String {
        KeyboardShortcuts.getShortcut(for: name)?.description ?? "Not set"
    }
}
