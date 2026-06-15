//
//  MenuController.swift
//  HiddenBarIcons
//

import Cocoa
import Sparkle
import SwiftUI

@MainActor
class MenuController: NSObject, NSMenuItemValidation {
    // MARK: - Properties

    private var preferencesWindow: NSWindow?
    private let updaterController: SPUStandardUpdaterController
    var displayModeManager: DisplayModeManager?
    var hiddenAppsScanner: MenuBarExtrasScanner?

    private static let hiddenAppItemTag = 8888
    private static let hiddenAppMenuItemMinWidth: CGFloat = 240
    private static let hiddenAppMenuItemMaxWidth: CGFloat = 420

    // MARK: - Initialization

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        super.init()
    }

    // MARK: - Context Menu

    func createContextMenu() -> NSMenu {
        let menu = NSMenu()

        self.addHiddenAppsItemsIfNeeded(to: menu)

        // Add "Hide Notch" / "Show Notch" toggle only if Mac has a notch
        if DeviceInformation.hasNotch {
            let is16by10 = self.isCurrentResolution16by10()
            let notchItem = NSMenuItem(
                title: is16by10 ? String(localized: "Show Notch") : String(localized: "Hide Notch"),
                action: #selector(self.toggleNotch(_:)),
                keyEquivalent: ""
            )
            notchItem.target = self
            menu.addItem(notchItem)
            menu.addItem(NSMenuItem.separator())
        }

        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences..."),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(
            title: String(localized: "About HiddenBarIcons"),
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updatesItem = NSMenuItem(
            title: String(localized: "Check for Updates..."),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Hidden Apps

    private func addHiddenAppsItemsIfNeeded(to menu: NSMenu) {
        let enabled = UserDefaults.standard.object(forKey: PreferenceKeys.showHiddenAppsInMenu) as? Bool
            ?? PreferenceDefaults.showHiddenAppsInMenu
        let trusted = AccessibilityManager.isTrusted()
        DZLog("contextMenu: hiddenApps enabled=\(enabled) trusted=\(trusted) scanner=\(self.hiddenAppsScanner != nil)")
        guard enabled, trusted, let scanner = self.hiddenAppsScanner else { return }

        let refreshItem = self.makeRefreshMenuItem()
        menu.addItem(refreshItem)

        // Render from the most recent cache; the scanner refreshes itself
        // off the main thread so this method never blocks on AX calls.
        let hidden = scanner.currentHidden()
        DZLog("contextMenu: scanner returned \(hidden.count) cached item(s)")
        self.insertHiddenAppItems(hidden, into: menu, after: refreshItem)
    }

    private func insertHiddenAppItems(
        _ items: [HiddenStatusItem],
        into menu: NSMenu,
        after anchorItem: NSMenuItem
    ) {
        guard let anchorIndex = menu.items.firstIndex(of: anchorItem) else { return }

        let allowRightClick = UserDefaults.standard.object(forKey: PreferenceKeys.allowRightClickHiddenApps) as? Bool
            ?? PreferenceDefaults.allowRightClickHiddenApps
        let customRowWidth = Self.hiddenAppMenuItemWidth(for: items)

        var insertIndex = anchorIndex + 1
        for item in items {
            let menuItem = allowRightClick
                ? self.makeCustomHiddenAppMenuItem(item, width: customRowWidth)
                : self.makeNativeHiddenAppMenuItem(item)
            menu.insertItem(menuItem, at: insertIndex)
            insertIndex += 1
        }

        if !items.isEmpty {
            menu.insertItem(NSMenuItem.separator(), at: insertIndex)
        }
    }

    private func makeNativeHiddenAppMenuItem(_ item: HiddenStatusItem) -> NSMenuItem {
        let mi = NSMenuItem(
            title: item.appName,
            action: #selector(self.openHiddenAppMenuItem(_:)),
            keyEquivalent: ""
        )
        mi.target = self
        mi.image = item.icon
        mi.representedObject = item
        mi.tag = Self.hiddenAppItemTag
        return mi
    }

    private func makeCustomHiddenAppMenuItem(
        _ item: HiddenStatusItem,
        width: CGFloat
    ) -> NSMenuItem {
        let mi = NSMenuItem()
        mi.representedObject = item
        mi.tag = Self.hiddenAppItemTag
        let view = HiddenAppMenuItemView(
            title: item.appName,
            icon: item.icon,
            width: width
        )
        view.onOpen = { [weak self] action in
            self?.hiddenAppsScanner?.openMenu(item, action: action)
        }
        mi.view = view
        return mi
    }

    private static func hiddenAppMenuItemWidth(for items: [HiddenStatusItem]) -> CGFloat {
        let titleWidth = items
            .map { item in
                (item.appName as NSString).size(withAttributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                ]).width
            }
            .max() ?? 0
        return min(max(Self.hiddenAppMenuItemMinWidth, titleWidth + 52), Self.hiddenAppMenuItemMaxWidth)
    }

    private func makeRefreshMenuItem() -> NSMenuItem {
        let refreshItem = NSMenuItem(
            title: String(localized: "Refresh hidden apps"),
            action: #selector(self.refreshHiddenApps(_:)),
            keyEquivalent: ""
        )
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        return refreshItem
    }

    private func isCurrentResolution16by10() -> Bool {
        let displayID = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return false }

        let width = Double(mode.width)
        let height = Double(mode.height)

        // 16:10 = 1.6, with some tolerance for rounding
        let aspectRatio = width / height
        return abs(aspectRatio - 1.6) < 0.01
    }

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(self.toggleNotch(_:)) {
            // Disable when built-in display is not active (lid closed with external monitor)
            return self.displayModeManager?.isBuiltInDisplayActive ?? false
        }
        return true
    }

    // MARK: - Menu Actions

    @objc
    private func toggleNotch(_: Any?) {
        self.displayModeManager?.toggle()
    }

    @objc
    private func showPreferences(_: Any?) {
        self.showPreferencesWindow()
    }

    @objc
    private func showAbout(_: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc
    private func checkForUpdates(_: Any?) {
        self.updaterController.checkForUpdates(nil)
    }

    @objc
    private func refreshHiddenApps(_: Any?) {
        self.hiddenAppsScanner?.refreshHidden()
    }

    @objc
    private func openHiddenAppMenuItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? HiddenStatusItem else { return }

        let action: HiddenAppOpenAction = NSApp.currentEvent?.modifierFlags.contains(.option) == true
            ? .contextMenu
            : .primary
        let scanner = self.hiddenAppsScanner
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            scanner?.openMenu(item, action: action)
        }
    }

    @objc
    private func quit(_: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Preferences Window

    func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if self.preferencesWindow == nil {
            let contentView = PreferencesView()
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Welcome to HiddenBarIcons")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 640, height: 520))
            window.center()

            self.preferencesWindow = window
        }

        self.preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}
