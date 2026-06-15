//
//  AccessibilityManager.swift
//  HiddenBarIcons
//

import AppKit
import ApplicationServices

/// Thin wrapper around the macOS Accessibility permission APIs.
enum AccessibilityManager {
    /// Returns true if the process is currently trusted for the Accessibility API.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system prompt that asks the user to grant Accessibility access.
    /// Returns the current trust state (will be false until the user toggles the app on).
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings directly on the Accessibility pane.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
