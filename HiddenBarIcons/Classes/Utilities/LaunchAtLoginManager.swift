//
//  LaunchAtLoginManager.swift
//  HiddenBarIcons
//

import AppKit
import Foundation
import os
import ServiceManagement

/// Manages whether HiddenBarIcons opens automatically at login.
///
/// Backed by `SMAppService.mainApp` — the modern login-item API, with no legacy
/// helper bundle. We call it directly rather than pulling in a package: it is a few
/// lines, and a direct wrapper fits the small static-manager pattern already used in
/// this app (e.g. `AccessibilityManager`). The injectable system calls keep the logic
/// unit-testable without touching the real login-item database.
///
/// `SMAppService.mainApp` registration works for a non-sandboxed `LSUIElement` app
/// and persists across logout/reboot; no entitlement is required.
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    /// Whether this process was started by the system as a login item, as opposed to
    /// being opened by the user. The open-application Apple event of a login-item
    /// launch carries `keyAELaunchedAsLogInItem`. That event is only current while it
    /// is being dispatched, so this must first be read inside
    /// `applicationDidFinishLaunching` (it is — via `StatusBarController.init`);
    /// later reads return the value captured then.
    static let wasLaunchedAtLogin: Bool = {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }()

    /// Whether HiddenBarIcons is currently registered as an enabled login item.
    @Published private(set) var isEnabled: Bool

    private let probe: () -> Bool
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let log = Logger(subsystem: "com.mekedron.HiddenBarIcons", category: "LaunchAtLogin")

    init(
        probe: @escaping () -> Bool = LaunchAtLoginManager.systemIsEnabled,
        register: @escaping () throws -> Void = LaunchAtLoginManager.systemRegister,
        unregister: @escaping () throws -> Void = LaunchAtLoginManager.systemUnregister
    ) {
        self.probe = probe
        self.register = register
        self.unregister = unregister
        self.isEnabled = probe()
    }

    /// Registers or unregisters the login item, then republishes the real resulting
    /// state. A failed system call is logged and swallowed: `isEnabled` always tracks
    /// what the system reports, never the requested value, so the toggle can never lie.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try register()
            } else {
                try unregister()
            }
        } catch {
            let action = enabled ? "register" : "unregister"
            log.error(
                "Failed to \(action, privacy: .public) login item: \(error.localizedDescription, privacy: .public)"
            )
        }
        refresh()
    }

    /// Re-reads the live registration state and publishes any change. Lets the toggle
    /// reflect approvals/removals the user made in System Settings while away.
    func refresh() {
        let current = probe()
        if current != isEnabled {
            isEnabled = current
        }
    }

    // MARK: - Live system implementations

    nonisolated static func systemIsEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers the main app as a login item. If it is already enabled, unregister
    /// first — re-registering an enabled service throws on some macOS versions.
    nonisolated static func systemRegister() throws {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        }
        try service.register()
    }

    nonisolated static func systemUnregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
