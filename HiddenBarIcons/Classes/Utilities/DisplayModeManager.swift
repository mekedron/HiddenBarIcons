//
//  DisplayModeManager.swift
//  HiddenBarIcons
//

import Cocoa
import CoreGraphics

@MainActor
class DisplayModeManager {
    // MARK: - Properties

    private var originalMode: CGDisplayMode?

    // MARK: - Initialization

    init() {
        // Save the original display mode on launch
        let displayID = CGMainDisplayID()
        self.originalMode = CGDisplayCopyDisplayMode(displayID)
    }

    // MARK: - Public Methods

    /// Returns true if the built-in display is currently active (lid open).
    var isBuiltInDisplayActive: Bool {
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)

        guard CGGetActiveDisplayList(16, &activeDisplays, &displayCount) == .success else {
            return false
        }

        for i in 0..<Int(displayCount) {
            if CGDisplayIsBuiltin(activeDisplays[i]) != 0 {
                return true
            }
        }

        return false
    }

    func toggle() {
        if self.isCurrentResolution16by10() {
            self.showNotch()
        } else {
            self.hideNotch()
        }
    }

    func restoreOriginalModeIfNeeded() {
        let displayID = CGMainDisplayID()
        guard
            let original = originalMode,
            let current = CGDisplayCopyDisplayMode(displayID) else { return }

        // Only restore if the mode has changed
        if current.width != original.width || current.height != original.height {
            self.switchDisplayMode(displayID: displayID, to: original)
        }
    }

    func hideNotch() {
        let displayID = CGMainDisplayID()

        guard let currentMode = CGDisplayCopyDisplayMode(displayID) else { return }

        // Find a notchless mode (same width, smaller height - 16:10 aspect ratio)
        guard let notchlessMode = findNotchlessMode(for: displayID, currentMode: currentMode) else {
            DZLog("No notchless mode found")
            return
        }

        self.switchDisplayMode(displayID: displayID, to: notchlessMode)
    }

    func showNotch() {
        let displayID = CGMainDisplayID()

        guard let currentMode = CGDisplayCopyDisplayMode(displayID) else { return }

        // Find the notched mode (same width, larger height)
        guard let notchedMode = findNotchedMode(for: displayID, currentMode: currentMode) else {
            DZLog("No notched mode found")
            return
        }

        self.switchDisplayMode(displayID: displayID, to: notchedMode)
    }

    // MARK: - Private Methods

    private func isCurrentResolution16by10() -> Bool {
        let displayID = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return false }

        let width = Double(mode.width)
        let height = Double(mode.height)

        // 16:10 = 1.6, with some tolerance
        let aspectRatio = width / height
        return abs(aspectRatio - 1.6) < 0.01
    }

    private func findNotchlessMode(for displayID: CGDirectDisplayID, currentMode: CGDisplayMode) -> CGDisplayMode? {
        guard let allModes = getAllDisplayModes(for: displayID) else { return nil }

        let currentWidth = currentMode.width
        let currentHeight = currentMode.height
        let currentRefresh = currentMode.refreshRate

        // Look for a mode with same width but smaller height (16:10)
        let candidates = allModes.filter { mode in
            mode.width == currentWidth &&
                mode.height < currentHeight &&
                mode.isUsableForDesktopGUI()
        }

        return self.selectBestMode(from: candidates, preferringRefreshRate: currentRefresh, preferLargerHeight: true)
    }

    private func findNotchedMode(for displayID: CGDirectDisplayID, currentMode: CGDisplayMode) -> CGDisplayMode? {
        guard let allModes = getAllDisplayModes(for: displayID) else { return nil }

        let currentWidth = currentMode.width
        let currentHeight = currentMode.height
        let currentRefresh = currentMode.refreshRate

        // Look for a mode with same width but larger height (notched/native)
        let candidates = allModes.filter { mode in
            mode.width == currentWidth &&
                mode.height > currentHeight &&
                mode.isUsableForDesktopGUI()
        }

        return self.selectBestMode(from: candidates, preferringRefreshRate: currentRefresh, preferLargerHeight: false)
    }

    private func getAllDisplayModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode]? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]
    }

    private func selectBestMode(
        from candidates: [CGDisplayMode],
        preferringRefreshRate targetRefresh: Double,
        preferLargerHeight: Bool
    )
        -> CGDisplayMode?
    {
        let sorted = candidates.sorted { a, b in
            // Sort by height
            if a.height != b.height {
                return preferLargerHeight ? (a.height > b.height) : (a.height < b.height)
            }
            // Prefer matching refresh rate
            let aMatchesRefresh = abs(a.refreshRate - targetRefresh) < 1
            let bMatchesRefresh = abs(b.refreshRate - targetRefresh) < 1
            if aMatchesRefresh != bMatchesRefresh {
                return aMatchesRefresh
            }
            return false
        }

        return sorted.first
    }

    @discardableResult
    private func switchDisplayMode(displayID: CGDirectDisplayID, to mode: CGDisplayMode) -> Bool {
        var config: CGDisplayConfigRef?

        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config else {
            DZLog("Failed to begin display configuration: \(beginError)")
            return false
        }

        let configError = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        guard configError == .success else {
            DZLog("Failed to configure display mode: \(configError)")
            CGCancelDisplayConfiguration(config)
            return false
        }

        let completeError = CGCompleteDisplayConfiguration(config, .forSession)
        guard completeError == .success else {
            DZLog("Failed to complete display configuration: \(completeError)")
            return false
        }

        return true
    }
}
