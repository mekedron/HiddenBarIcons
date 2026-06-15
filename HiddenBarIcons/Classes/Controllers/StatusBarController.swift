//
//  StatusBarController.swift
//  HiddenBarIcons
//

import Cocoa
import Sparkle

extension Notification.Name {
    static let separatorVisibilityPreferenceChanged = Notification.Name("HBISeparatorVisibilityPreferenceChanged")
}

@MainActor
class StatusBarController: NSObject {
    // MARK: - Status Bar Items

    /// The arrow button for expand/collapse
    private let arrowItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    /// The pipe separator that expands to hide items
    private let separatorItem = NSStatusBar.system.statusItem(withLength: 20)

    // MARK: - Properties

    private let menuController: MenuController
    private let displayModeManager = DisplayModeManager()
    private let activationPolicyManager = ActivationPolicyManager()
    private let hiddenAppsScanner = MenuBarExtrasScanner()
    private var autoCollapseTimer: Timer?
    private var commandKeyPollTimer: Timer?
    private var lastObservedCommandPressed = false
    private var separatorPreferenceObserver: NSObjectProtocol?
    private let commandKeyPollInterval: TimeInterval = 0.05

    private let separatorHiddenLength: CGFloat = 0
    private let separatorVisibleLength: CGFloat = 20
    private let separatorExpandedLength: CGFloat = 10000

    private var hideSeparatorWhenExpanded: Bool {
        UserDefaults.standard.object(forKey: PreferenceKeys.hideSeparatorWhenExpanded) as? Bool
            ?? PreferenceDefaults.hideSeparatorWhenExpanded
    }

    private var isCollapsed: Bool {
        self.separatorItem.length == self.separatorExpandedLength
    }

    /// Check if separator is in valid position (to the left of arrow)
    private var isSeparatorValidPosition: Bool {
        guard
            let arrowX = arrowItem.button?.window?.frame.origin.x,
            let separatorX = separatorItem.button?.window?.frame.origin.x else { return false }

        // Separator should be to the LEFT of arrow (lower X value)
        return separatorX < arrowX
    }

    // MARK: - Initialization

    init(updaterController: SPUStandardUpdaterController) {
        self.menuController = MenuController(updaterController: updaterController)
        super.init()
        self.setupUI()
        self.setupDisplayModeManager()
        self.setupHiddenAppsScanner()
        self.installSeparatorPreferenceObserver()

        // Auto-collapse after 1 second on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseStatusBar()
        }

        self.showPreferencesOnLaunchIfNeeded()
    }

    deinit {
        self.commandKeyPollTimer?.invalidate()
        if let observer = self.separatorPreferenceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupDisplayModeManager() {
        self.menuController.displayModeManager = self.displayModeManager
    }

    private func setupHiddenAppsScanner() {
        self.menuController.hiddenAppsScanner = self.hiddenAppsScanner
        self.hiddenAppsScanner.expandRequested = { [weak self] in
            self?.expandStatusBar()
        }
        self.hiddenAppsScanner.separatorFrameProvider = { [weak self] in
            self?.separatorItem.button?.window?.frame
        }

        let enabled = UserDefaults.standard.object(forKey: PreferenceKeys.showHiddenAppsInMenu) as? Bool
            ?? PreferenceDefaults.showHiddenAppsInMenu
        if enabled {
            self.hiddenAppsScanner.warmCacheInBackground()
        }
    }

    private func setupUI() {
        // Setup separator (pipe) - created first, will be on the left
        if let button = separatorItem.button {
            button.image = NSImage(named: "separator")
        }
        self.separatorItem.autosaveName = "hiddenbaricons_separator"

        // Setup arrow button - created second, will be on the right
        if let button = arrowItem.button {
            button.image = NSImage(named: "collapse")
            button.target = self
            button.action = #selector(self.arrowButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.arrowItem.autosaveName = "hiddenbaricons_arrow"
    }

    private func showPreferencesOnLaunchIfNeeded() {
        let showOnLaunch = UserDefaults.standard.object(forKey: PreferenceKeys.showPreferencesOnLaunch) as? Bool
            ?? PreferenceDefaults.showPreferencesOnLaunch

        if showOnLaunch {
            self.menuController.showPreferencesWindow()
        }
    }

    // MARK: - Expand/Collapse

    @objc
    private func arrowButtonClicked(_: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        let isRightClick = event.type == .rightMouseUp
        let isControlClick = event.type == .leftMouseUp && event.modifierFlags.contains(.control)

        if isRightClick || isControlClick {
            // Show context menu on right-click or control-click
            self.arrowItem.menu = self.menuController.createContextMenu()
            self.arrowItem.button?.performClick(nil)
            self.arrowItem.menu = nil
        } else {
            // Toggle expand/collapse on left-click
            self.toggleExpandCollapse()
        }
    }

    func toggleExpandCollapse() {
        if self.isCollapsed {
            self.expandStatusBar()
        } else {
            if !self.isSeparatorValidPosition {
                self.showInvalidPositionAlert()
            }
            self.collapseStatusBar()
        }
    }

    private func showInvalidPositionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Separator in Wrong Position")
        alert
            .informativeText =
            String(
                localized: "The separator is on the wrong side. Please drag the separator (|) to the left of the arrow icon in your status bar for HiddenBarIcons to work correctly."
            )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    func restoreDisplayModeIfNeeded() {
        self.displayModeManager.restoreOriginalModeIfNeeded()
    }

    private func collapseStatusBar() {
        guard self.isSeparatorValidPosition, !self.isCollapsed else {
            self.startAutoCollapseTimerIfNeeded()
            return
        }

        // Restore the pipe image (it's nil'd while expanded without Command held).
        self.separatorItem.button?.image = NSImage(named: "separator")
        self.separatorItem.length = self.separatorExpandedLength

        if let button = arrowItem.button {
            button.image = NSImage(named: "expand")
        }

        self.updateCommandKeyPolling()
        self.activationPolicyManager.deactivate()

        // Warm the hidden-apps cache once the bar is actually hiding items:
        // the scanner short-circuits while the separator is short, so the
        // init-time warm is effectively a no-op until first collapse.
        let hiddenAppsEnabled = UserDefaults.standard.object(forKey: PreferenceKeys.showHiddenAppsInMenu) as? Bool
            ?? PreferenceDefaults.showHiddenAppsInMenu
        if hiddenAppsEnabled {
            self.hiddenAppsScanner.warmCacheInBackground()
        }
    }

    func expandStatusBar() {
        guard self.isCollapsed else { return }

        let shouldShow = !self.hideSeparatorWhenExpanded || NSEvent.modifierFlags.contains(.command)
        self.applySeparatorVisible(shouldShow)

        if let button = arrowItem.button {
            button.image = NSImage(named: "collapse")
        }

        self.updateCommandKeyPolling()
        self.activationPolicyManager.activateIfEnabled()
        self.startAutoCollapseTimerIfNeeded()
    }

    /// Switches the separator between its shown (20px + pipe image) and
    /// hidden (0px, no image) states while the app is expanded. The status
    /// item itself is never removed, so its position is preserved.
    private func applySeparatorVisible(_ visible: Bool) {
        self.separatorItem.length = visible ? self.separatorVisibleLength : self.separatorHiddenLength
        self.separatorItem.button?.image = visible ? NSImage(named: "separator") : nil
    }

    // MARK: - Auto-Collapse Timer

    private func startAutoCollapseTimerIfNeeded() {
        self.autoCollapseTimer?.invalidate()

        let isAutoCollapseEnabled = UserDefaults.standard.object(forKey: PreferenceKeys.isAutoCollapseEnabled) as? Bool
            ?? PreferenceDefaults.isAutoCollapseEnabled

        guard isAutoCollapseEnabled, !self.isCollapsed else { return }

        let delay = UserDefaults.standard.object(forKey: PreferenceKeys.autoCollapseDelay) as? Int
            ?? PreferenceDefaults.autoCollapseDelay

        self.autoCollapseTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(delay),
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseStatusBar()
            }
        }
    }

    // MARK: - Command Key Polling

    /// Polls `NSEvent.modifierFlags` while the app is expanded with the
    /// hide-separator preference on. This works without Accessibility access
    /// (unlike a global `flagsChanged` event monitor, which requires it),
    /// so the separator can always be revealed by holding ⌘.
    private func updateCommandKeyPolling() {
        let shouldPoll = !self.isCollapsed && self.hideSeparatorWhenExpanded
        if shouldPoll {
            self.startCommandKeyPolling()
        } else {
            self.stopCommandKeyPolling()
        }
    }

    private func startCommandKeyPolling() {
        guard self.commandKeyPollTimer == nil else { return }
        self.lastObservedCommandPressed = NSEvent.modifierFlags.contains(.command)
        self.commandKeyPollTimer = Timer.scheduledTimer(
            withTimeInterval: self.commandKeyPollInterval,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pollCommandKey()
            }
        }
    }

    private func stopCommandKeyPolling() {
        self.commandKeyPollTimer?.invalidate()
        self.commandKeyPollTimer = nil
    }

    private func pollCommandKey() {
        guard !self.isCollapsed, self.hideSeparatorWhenExpanded else {
            self.stopCommandKeyPolling()
            return
        }
        let commandHeld = NSEvent.modifierFlags.contains(.command)
        guard commandHeld != self.lastObservedCommandPressed else { return }
        self.lastObservedCommandPressed = commandHeld
        self.applySeparatorVisible(commandHeld)
    }

    private func installSeparatorPreferenceObserver() {
        self.separatorPreferenceObserver = NotificationCenter.default.addObserver(
            forName: .separatorVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSeparatorForCurrentState()
            }
        }
    }

    private func refreshSeparatorForCurrentState() {
        guard !self.isCollapsed else { return }
        let shouldShow = !self.hideSeparatorWhenExpanded || NSEvent.modifierFlags.contains(.command)
        self.applySeparatorVisible(shouldShow)
        self.updateCommandKeyPolling()
    }
}
