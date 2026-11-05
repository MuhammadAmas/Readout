import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

struct ShortcutRecorder: View {
    let name: KeyboardShortcuts.Name
    let others: [KeyboardShortcuts.Name]

    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(isRecording ? "Type a shortcut…" : (shortcut?.description ?? "Record Shortcut"))
                        .monospacedDigit()
                        .frame(minWidth: 130)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                .help(isRecording ? "Press keys with ⌃, ⌥ or ⌘. Esc cancels, Delete clears." : "Click to change")

                Button("Default") {
                    KeyboardShortcuts.reset(name)
                    refresh()
                }
                .buttonStyle(.borderless)
                .disabled(isRecording)
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: refresh)
        .onDisappear(perform: stopRecording)
    }

    private func refresh() {
        shortcut = KeyboardShortcuts.getShortcut(for: name)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        problem = nil
        isRecording = true
        KeyboardShortcuts.isEnabled = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        KeyboardShortcuts.isEnabled = true
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)

        if modifiers.isEmpty, keyCode == kVK_Escape {
            stopRecording()
            return
        }
        if modifiers.isEmpty, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            KeyboardShortcuts.setShortcut(nil, for: name)
            refresh()
            stopRecording()
            return
        }
        guard !modifiers.subtracting(.shift).isEmpty else {
            problem = "Include ⌃, ⌥ or ⌘ so the shortcut doesn't clash with typing."
            NSSound.beep()
            return
        }
        guard let candidate = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return
        }
        if others.contains(where: { KeyboardShortcuts.getShortcut(for: $0) == candidate }) {
            problem = "\(candidate.description) is already used by Readout."
            NSSound.beep()
            return
        }
        problem = nil
        KeyboardShortcuts.setShortcut(candidate, for: name)
        refresh()
        stopRecording()
    }
}
