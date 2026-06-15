//
//  ActivationPolicyManager.swift
//  HiddenBarIcons
//

import Cocoa

/// Manages the app's activation policy to show the app's dock icon temporarily
/// and display an empty menu bar, giving more space for status bar items.
@MainActor
class ActivationPolicyManager {
    // MARK: - Properties

    private var resignActiveObserver: NSObjectProtocol?
    private var emptyMenu: NSMenu?

    private var isActive: Bool {
        NSApp.activationPolicy() == .regular
    }

    // MARK: - Initialization

    init() {
        // Observe when app loses focus to deactivate
        self.resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.deactivate()
            }
        }

        // Create minimal menu for full expand mode (only Quit item)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let quitItem = NSMenuItem(
            title: String(localized: "Quit HiddenBarIcons"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        self.emptyMenu = mainMenu
    }

    deinit {
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Private Methods

    private func performActivation() {
        // Set minimal menu bar for full expand mode
        NSApp.mainMenu = self.emptyMenu

        NSApp.setActivationPolicy(.regular)
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            NSRunningApplication.current.activate(from: frontApp)
        } else {
            NSApp.activate()
        }
    }

    // MARK: - Public Methods

    /// Activates full expand mode if the preference is enabled.
    /// Switches to regular activation policy and activates the app.
    func activateIfEnabled() {
        let isFullExpandEnabled = UserDefaults.standard.object(forKey: PreferenceKeys.isFullExpandEnabled) as? Bool
            ?? PreferenceDefaults.isFullExpandEnabled

        guard isFullExpandEnabled, !self.isActive else { return }

        self.performActivation()
    }

    /// Deactivates full expand mode.
    /// Switches back to accessory activation policy and deactivates the app.
    func deactivate() {
        guard self.isActive else { return }

        // Yield activation to another app
        if let nextApp = NSWorkspace.shared.runningApplications.first(where: { $0 != .current }) {
            NSApp.yieldActivation(to: nextApp)
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
