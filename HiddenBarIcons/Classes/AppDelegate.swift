//
//  AppDelegate.swift
//  HiddenBarIcons
//

import Cocoa
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    var statusBarController: StatusBarController?
    var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_: Notification) {
        self.statusBarController = StatusBarController(updaterController: self.updaterController)
        self.hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.statusBarController?.toggleExpandCollapse()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        self.statusBarController?.restoreDisplayModeIfNeeded()
    }

    // MARK: - SPUStandardUserDriverDelegate

    func supportsGentleScheduledUpdateReminders() -> Bool {
        true
    }
}
