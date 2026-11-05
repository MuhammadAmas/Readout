import SwiftUI

@main
struct ReadoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, queue: model.queue)
        } label: {
            MenuBarIcon(queue: model.queue)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Preferences.register()

        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") {
            SelfTest.run()
            return
        }

        let model = AppModel.shared
        Hotkeys.register(model: model)

        if arguments.contains("--settings") {
            model.showSettings()
        } else if arguments.contains("--onboarding") {
            model.showOnboarding()
        } else if !AccessibilityPermission.isTrusted || !UserDefaults.standard.bool(forKey: Preferences.hasCompletedOnboarding) {
            model.showOnboarding()
        }
        if let index = arguments.firstIndex(of: "--read"), arguments.indices.contains(index + 1) {
            model.read(arguments[index + 1])
        }
        if arguments.contains(Updater.relaunchArgument) {
            model.hud.show("Readout updated to \(Updater.shared.currentVersion)", symbol: "arrow.down.circle.fill")
        }
        Updater.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showSettings()
        return false
    }
}
