import AppKit
import ApplicationServices

@MainActor
enum SelectionReader {
    enum Source: String {
        case accessibility = "Accessibility"
        case clipboard = "Copy"
    }

    struct Capture {
        let text: String
        let source: Source
    }

    static func capture() async -> Capture? {
        let app = NSWorkspace.shared.frontmostApplication
        Log.capture.info("Capturing from \(app?.bundleIdentifier ?? "unknown", privacy: .public)")
        switch AccessibilitySelection.read() {
        case .text(let text):
            Log.capture.info("Accessibility returned \(text.count, privacy: .public) characters")
            return Capture(text: text, source: .accessibility)
        case .secureField:
            Log.capture.info("Focused element is a secure text field; not reading")
            return nil
        case .unavailable:
            break
        }
        guard let text = await ClipboardSelection.copySelection() else { return nil }
        Log.capture.info("Copy fallback returned \(text.count, privacy: .public) characters")
        return Capture(text: text, source: .clipboard)
    }
}

enum AccessibilitySelection {
    enum Result {
        case text(String)
        case secureField
        case unavailable
    }

    private static let timeout: Float = 0.25

    static func read() -> Result {
        enableElectronAccessibility()
        guard let element = focusedElement() else {
            Log.capture.info("Accessibility: no focused element")
            return .unavailable
        }
        AXUIElementSetMessagingTimeout(element, timeout)
        let role = string(element, kAXRoleAttribute) ?? "none"
        let subrole = string(element, kAXSubroleAttribute) ?? "none"
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secureField
        }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        let text = value as? String
        Log.capture.info("Accessibility: role \(role, privacy: .public)/\(subrole, privacy: .public), selected text error \(error.rawValue, privacy: .public), \(text?.count ?? -1, privacy: .public) characters")
        if let text, text.contains(where: { !$0.isWhitespace }) {
            return .text(text)
        }
        return .unavailable
    }

    private static func enableElectronAccessibility() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)
        if let element = element(systemWide, kAXFocusedUIElementAttribute) {
            return element
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        return element(application, kAXFocusedUIElementAttribute)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(parent, attribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Log.capture.info("Accessibility: \(attribute, privacy: .public) failed with \(error.rawValue, privacy: .public)")
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

@MainActor
enum ClipboardSelection {
    static func copySelection(timeout: TimeInterval = 0.45) async -> String? {
        let pasteboard = NSPasteboard.general
        await waitForModifierRelease(limit: 0.3)

        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        guard KeyPress.copy() else {
            Log.capture.error("Copy fallback: could not create the ⌘C key events")
            return nil
        }
        let started = Date()

        let deadline = Date().addingTimeInterval(timeout)
        while pasteboard.changeCount == before, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard pasteboard.changeCount != before else {
            Log.capture.info("Copy fallback: clipboard did not change within \(Int(timeout * 1000), privacy: .public) ms")
            return nil
        }
        Log.capture.info("Copy fallback: clipboard changed after \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")

        var text = pasteboard.string(forType: .string)
        let settleDeadline = Date().addingTimeInterval(0.15)
        while text == nil, Date() < settleDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            text = pasteboard.string(forType: .string)
        }
        snapshot.restore(to: pasteboard)
        Log.capture.info("Copy fallback: restored \(snapshot.items.count, privacy: .public) clipboard items")

        guard let text, text.contains(where: { !$0.isWhitespace }) else { return nil }
        return text
    }

    private static func waitForModifierRelease(limit: TimeInterval) async {
        let held: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let deadline = Date().addingTimeInterval(limit)
        while !NSEvent.modifierFlags.intersection(held).isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let stillHeld = NSEvent.modifierFlags.intersection(held)
        if !stillHeld.isEmpty {
            Log.capture.info("Copy fallback: modifiers still held (\(stillHeld.rawValue, privacy: .public)), sending ⌘C anyway")
        }
    }
}
