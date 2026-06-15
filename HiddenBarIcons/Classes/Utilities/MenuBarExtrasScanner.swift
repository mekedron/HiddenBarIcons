//
//  MenuBarExtrasScanner.swift
//  HiddenBarIcons
//

import AppKit
import ApplicationServices

/// Identifies a status bar item belonging to another app that is currently
/// pushed off-screen by the separator.
struct HiddenStatusItem {
    let appName: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let element: AXUIElement
}

enum HiddenAppOpenAction {
    case primary
    case contextMenu
}

extension Notification.Name {
    static let warmHiddenAppsCache = Notification.Name("HBIWarmHiddenAppsCache")
}

/// Wraps a CF reference (`AXUIElement`) so it can cross actor boundaries
/// when the background scan hands raw results back to the main actor.
/// CF accessibility references are safe to retain across threads.
private struct SendableAXElement: @unchecked Sendable {
    let value: AXUIElement
}

/// Enumerates other apps' menu bar extras via the Accessibility API and
/// simulates clicks on the off-screen ones.
@MainActor
final class MenuBarExtrasScanner {
    /// Invoked when a click/showMenu wants the status bar to be expanded first.
    var expandRequested: (@MainActor () -> Void)?

    /// Returns the AppKit screen frame of the app's separator NSStatusItem.
    /// It anchors hidden item detection to the menu bar on the same display
    /// instead of assuming the active menu bar is always near global y = 0.
    var separatorFrameProvider: (@MainActor () -> CGRect?)?

    /// Called whenever `cachedHidden` is replaced after a background refresh.
    var onCacheUpdated: (@MainActor () -> Void)?

    private var warmObserver: NSObjectProtocol?

    /// Last successful scan result. Reads from this are O(1) and never block.
    private(set) var cachedHidden: [HiddenStatusItem] = []

    private var refreshTask: Task<Void, Never>?
    private var pidsWithExtras: Set<pid_t> = []
    private var lastFullScanAt: Date?
    private var appIconCache: [String: NSImage] = [:]

    private let axMessagingTimeout: Float = 0.2 // seconds per element
    private let fullRescanInterval: TimeInterval = 30 // re-discover new apps every 30s
    private let menuIconSize = NSSize(width: 16, height: 16)
    private let openVisibilityTimeout: TimeInterval = 1.5
    private let openVisibilityPollInterval: UInt64 = 50_000_000 // nanoseconds
    private let menuBarYTolerance: CGFloat = 12
    /// Above this width, the separator is expanded to its hide-other-items
    /// length (≈ 10000). Used to detect "collapsed" (= items hidden) state.
    private let collapsedSeparatorWidthThreshold: CGFloat = 1000

    fileprivate struct MenuBarReference: Sendable {
        let cutoffX: CGFloat
        let yRange: ClosedRange<CGFloat>
    }

    fileprivate struct AppSnapshot: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let localizedName: String?
        let activationPolicy: NSApplication.ActivationPolicy

        init(_ app: NSRunningApplication) {
            self.pid = app.processIdentifier
            self.bundleIdentifier = app.bundleIdentifier
            self.localizedName = app.localizedName
            self.activationPolicy = app.activationPolicy
        }
    }

    fileprivate struct ScreenInfo: Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
        let cgBounds: CGRect?

        init(_ screen: NSScreen) {
            self.frame = screen.frame
            self.visibleFrame = screen.visibleFrame
            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
            {
                self.cgBounds = CGDisplayBounds(displayID)
            } else {
                self.cgBounds = nil
            }
        }
    }

    fileprivate struct RawHiddenItem: Sendable {
        let pid: pid_t
        let element: SendableAXElement
        let position: CGPoint
        let displayName: String
        let bundleIdentifier: String?
    }

    fileprivate struct ScanResult: Sendable {
        let rawHidden: [RawHiddenItem]
        let freshPidsWithExtras: Set<pid_t>
        let elapsed: TimeInterval
        let appsChecked: Int
        let reference: MenuBarReference
    }

    // MARK: - Lifecycle

    init() {
        self.warmObserver = NotificationCenter.default.addObserver(
            forName: .warmHiddenAppsCache,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.warmCacheInBackground()
            }
        }
    }

    deinit {
        if let warmObserver {
            NotificationCenter.default.removeObserver(warmObserver)
        }
    }

    // MARK: - Public API

    /// Returns the last cached scan and schedules an async refresh.
    /// Safe to call from the menu-open path — never blocks on AX calls.
    @discardableResult
    func currentHidden() -> [HiddenStatusItem] {
        self.scheduleRefreshIfNeeded()
        return self.cachedHidden
    }

    /// Forces a fresh full scan in the background. Used by the explicit
    /// "Refresh" menu item; the new results land in `cachedHidden` and the
    /// `onCacheUpdated` callback fires when done.
    func refreshHidden() {
        self.appIconCache.removeAll()
        self.scheduleRefreshIfNeeded(forceFullScan: true, cancelExisting: true)
    }

    /// Kicks off a background scan to pre-populate the cache without
    /// blocking the main thread. Safe to call repeatedly.
    func warmCacheInBackground() {
        self.scheduleRefreshIfNeeded()
    }

    // MARK: - Open

    func openMenu(_ item: HiddenStatusItem, action: HiddenAppOpenAction) {
        self.performAfterExpand(item: item, action: action)
    }

    // MARK: - Refresh scheduling

    private func scheduleRefreshIfNeeded(
        forceFullScan: Bool = false,
        cancelExisting: Bool = false
    ) {
        if cancelExisting {
            self.refreshTask?.cancel()
            self.refreshTask = nil
        }
        guard self.refreshTask == nil else { return }
        guard AccessibilityManager.isTrusted() else { return }

        let separatorFrame = self.separatorFrameProvider?()

        // Detection only makes sense when the app is actually hiding items
        // (separator stretched to its expanded length). While expanded the
        // separator span is small and would misclassify every visible status
        // item as hidden, so we leave the cache untouched.
        let isStatusBarCollapsed = (separatorFrame?.width ?? 0)
            > self.collapsedSeparatorWidthThreshold
        guard isStatusBarCollapsed else {
            DZLog("scanHidden: skipped (status bar expanded, no items hidden)")
            return
        }

        let appSnapshots = NSWorkspace.shared.runningApplications.map(AppSnapshot.init)
        let screenInfos = NSScreen.screens.map(ScreenInfo.init)
        let pidsCache = self.pidsWithExtras
        let lastFullScanAt = self.lastFullScanAt
        let needsFullScan = forceFullScan
            || pidsCache.isEmpty
            || (lastFullScanAt.map { Date().timeIntervalSince($0) > self.fullRescanInterval } ?? true)
        let timeout = self.axMessagingTimeout
        let menuBarYTolerance = self.menuBarYTolerance
        let ownBundleId = Bundle.main.bundleIdentifier

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = MenuBarExtrasScanner.performScan(
                appSnapshots: appSnapshots,
                pidsWithExtras: pidsCache,
                needsFullScan: needsFullScan,
                separatorFrame: separatorFrame,
                screenInfos: screenInfos,
                menuBarYTolerance: menuBarYTolerance,
                axMessagingTimeout: timeout,
                ownBundleId: ownBundleId
            )
            let cancelled = Task.isCancelled
            await self?.handleScanCompletion(
                result: result,
                fullScan: needsFullScan,
                cancelled: cancelled
            )
        }
        self.refreshTask = task
    }

    private func handleScanCompletion(
        result: ScanResult,
        fullScan: Bool,
        cancelled: Bool
    ) {
        if !cancelled {
            self.applyScanResult(result, fullScan: fullScan)
            self.onCacheUpdated?()
        }
        self.refreshTask = nil
    }

    private func applyScanResult(_ result: ScanResult, fullScan: Bool) {
        if fullScan {
            self.pidsWithExtras = result.freshPidsWithExtras
            self.lastFullScanAt = Date()
        } else {
            self.pidsWithExtras.formUnion(result.freshPidsWithExtras)
        }

        let currentApps = NSWorkspace.shared.runningApplications
        let appsByPid: [pid_t: NSRunningApplication] = currentApps.reduce(into: [:]) { acc, app in
            guard app.processIdentifier > 0 else { return }
            acc[app.processIdentifier] = app
        }

        self.cachedHidden = result.rawHidden.map { raw in
            let icon = appsByPid[raw.pid].flatMap { self.icon(for: $0) }
            return HiddenStatusItem(
                appName: raw.displayName,
                bundleIdentifier: raw.bundleIdentifier,
                icon: icon,
                element: raw.element.value
            )
        }

        DZLog(
            "scanHidden: checked=\(result.appsChecked) " +
                "cached=\(self.pidsWithExtras.count) hidden=\(result.rawHidden.count) " +
                "cutoffX=\(result.reference.cutoffX) yRange=\(result.reference.yRange) full=\(fullScan) " +
                "elapsed=\(String(format: "%.0fms", result.elapsed * 1000))"
        )
    }

    // MARK: - Background scan (nonisolated)

    nonisolated
    private static func performScan(
        appSnapshots: [AppSnapshot],
        pidsWithExtras: Set<pid_t>,
        needsFullScan: Bool,
        separatorFrame: CGRect?,
        screenInfos: [ScreenInfo],
        menuBarYTolerance: CGFloat,
        axMessagingTimeout: Float,
        ownBundleId: String?
    ) -> ScanResult {
        let started = Date()
        let reference = Self.menuBarReference(
            separatorFrame: separatorFrame,
            screens: screenInfos,
            menuBarYTolerance: menuBarYTolerance
        )

        let appsToCheck: [AppSnapshot] = needsFullScan
            ? appSnapshots
            : appSnapshots.filter { pidsWithExtras.contains($0.pid) }

        var results: [RawHiddenItem] = []
        var freshPids: Set<pid_t> = []

        for app in appsToCheck {
            guard app.pid > 0 else { continue }
            switch app.activationPolicy {
            case .regular, .accessory: break
            default: continue
            }
            if let bid = app.bundleIdentifier, bid == ownBundleId { continue }

            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)

            guard let extras = Self.copyAttribute(
                element: appElement,
                attribute: "AXExtrasMenuBar"
            ) else { continue }
            let extrasElement = extras as! AXUIElement
            freshPids.insert(app.pid)

            guard let childrenValue = Self.copyAttribute(
                element: extrasElement,
                attribute: kAXChildrenAttribute as String
            ),
                let children = childrenValue as? [AXUIElement] else { continue }

            let appName = app.localizedName ?? app.bundleIdentifier ?? String(localized: "Unknown")

            for child in children {
                guard let position = Self.readPosition(element: child) else { continue }
                // Skip phantom items: zero-sized widgets, or anchored far below the
                // menu bar (Control Center exposes inactive widgets at (0, 1692)).
                guard let size = Self.readSize(element: child),
                      size.width > 0, size.height > 0,
                      Self.isHiddenStatusItem(position: position, reference: reference)
                else { continue }

                let label = Self.readLabel(element: child)
                let displayName: String
                if let label, label != appName {
                    displayName = "\(appName) — \(label)"
                } else {
                    displayName = appName
                }

                results.append(RawHiddenItem(
                    pid: app.pid,
                    element: SendableAXElement(value: child),
                    position: position,
                    displayName: displayName,
                    bundleIdentifier: app.bundleIdentifier
                ))
            }
        }

        results.sort { $0.position.x < $1.position.x }

        return ScanResult(
            rawHidden: results,
            freshPidsWithExtras: freshPids,
            elapsed: Date().timeIntervalSince(started),
            appsChecked: appsToCheck.count,
            reference: reference
        )
    }

    nonisolated
    private static func menuBarReference(
        separatorFrame: CGRect?,
        screens: [ScreenInfo],
        menuBarYTolerance: CGFloat
    ) -> MenuBarReference {
        guard let separatorFrame,
              let screen = Self.screen(containing: separatorFrame, in: screens),
              let cgBounds = screen.cgBounds
        else {
            return MenuBarReference(
                cutoffX: separatorFrame?.minX ?? 0,
                yRange: 0 ... 40
            )
        }

        let topInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let menuBarHeight = max(topInset, separatorFrame.height)
        let minY = cgBounds.minY - menuBarYTolerance
        let maxY = cgBounds.minY + menuBarHeight + menuBarYTolerance

        return MenuBarReference(
            cutoffX: separatorFrame.minX,
            yRange: minY ... maxY
        )
    }

    nonisolated
    private static func screen(containing frame: CGRect, in screens: [ScreenInfo]) -> ScreenInfo? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let screen = screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }
        return screens.max { lhs, rhs in
            Self.intersectionArea(lhs.frame, frame) < Self.intersectionArea(rhs.frame, frame)
        }
    }

    nonisolated
    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    nonisolated
    private static func isHiddenStatusItem(
        position: CGPoint,
        reference: MenuBarReference
    ) -> Bool {
        position.x < reference.cutoffX && reference.yRange.contains(position.y)
    }

    nonisolated
    private static func copyAttribute(element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    nonisolated
    private static func readPosition(element: AXUIElement) -> CGPoint? {
        guard let raw = Self.copyAttribute(
            element: element,
            attribute: kAXPositionAttribute as String
        ) else { return nil }
        var point = CGPoint.zero
        let axValue = raw as! AXValue
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    nonisolated
    private static func readSize(element: AXUIElement) -> CGSize? {
        guard let raw = Self.copyAttribute(
            element: element,
            attribute: kAXSizeAttribute as String
        ) else { return nil }
        var size = CGSize.zero
        let axValue = raw as! AXValue
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Tries common AX attributes that may carry a per-item description
    /// (e.g. "Wi-Fi", "Sound") for Control Center widgets.
    nonisolated
    private static func readLabel(element: AXUIElement) -> String? {
        let candidates = [
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            kAXHelpAttribute,
        ]
        for key in candidates {
            if let s = Self.copyAttribute(element: element, attribute: key as String) as? String,
               !s.isEmpty
            {
                return s
            }
        }
        return nil
    }

    // MARK: - Actions

    private func performAfterExpand(
        item: HiddenStatusItem,
        action: HiddenAppOpenAction
    ) {
        let element = item.element

        self.expandRequested?()
        Task { @MainActor in
            let clickPoint = await self.waitForVisibleClickPoint(on: element)

            if action == .contextMenu {
                self.simulateMouseClick(at: clickPoint, action: action, restoreMouse: true)
                return
            }

            self.performAccessibilityPress(on: element)
        }
    }

    private func icon(for app: NSRunningApplication) -> NSImage? {
        let cacheKey = app.bundleIdentifier ?? app.bundleURL?.path ?? String(app.processIdentifier)
        if let cached = self.appIconCache[cacheKey] {
            return cached
        }

        guard let image = self.bundleIcon(for: app) else { return nil }
        image.size = self.menuIconSize
        self.appIconCache[cacheKey] = image
        return image
    }

    private func bundleIcon(for app: NSRunningApplication) -> NSImage? {
        if let bundleURL = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
        return app.icon?.copy() as? NSImage
    }

    private func performAccessibilityPress(on element: AXUIElement) {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            DZLog("AX press failed (\(result.rawValue))")
        }
    }

    /// Synthesizes one real click at the status item's screen position.
    /// Requires the status bar to have already expanded so the item is on-screen.
    @discardableResult
    private func simulateMouseClick(
        at clickPoint: CGPoint?,
        action: HiddenAppOpenAction,
        restoreMouse: Bool
    ) -> Bool {
        guard let clickPoint else {
            DZLog("simulateMouseClick: no readable position/size")
            return false
        }
        DZLog("simulateMouseClick at \(clickPoint) action=\(action)")

        let button: CGMouseButton = action == .contextMenu ? .right : .left
        let downType: CGEventType = action == .contextMenu ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = action == .contextMenu ? .rightMouseUp : .leftMouseUp
        let originalMousePoint = restoreMouse ? CGEvent(source: nil)?.location : nil

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: clickPoint,
            mouseButton: button
        )
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: clickPoint,
            mouseButton: button
        )
        up?.post(tap: .cghidEventTap)

        if let originalMousePoint {
            self.restoreMousePositionAfterMenuOpens(to: originalMousePoint)
        }

        return true
    }

    private func waitForVisibleClickPoint(on element: AXUIElement) async -> CGPoint? {
        let timeoutAt = Date().addingTimeInterval(self.openVisibilityTimeout)

        while Date() < timeoutAt {
            if let clickPoint = self.clickPoint(for: element) {
                return clickPoint
            }

            try? await Task.sleep(nanoseconds: self.openVisibilityPollInterval)
        }

        return self.clickPoint(for: element)
    }

    private func restoreMousePositionAfterMenuOpens(to point: CGPoint) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            CGWarpMouseCursorPosition(point)
        }
    }

    private func clickPoint(for element: AXUIElement) -> CGPoint? {
        guard let position = Self.readPosition(element: element),
              let size = Self.readSize(element: element),
              size.width > 0,
              size.height > 0 else { return nil }

        let clickPoint = CGPoint(
            x: position.x + size.width / 2,
            y: position.y + size.height / 2
        )
        guard self.isPointOnAnyDisplay(clickPoint) else { return nil }
        return clickPoint
    }

    private func isPointOnAnyDisplay(_ point: CGPoint) -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else { return false }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        let result = displays.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(displayCount, buffer.baseAddress, &displayCount)
        }
        guard result == .success else { return false }

        return displays.prefix(Int(displayCount)).contains { display in
            CGDisplayBounds(display).contains(point)
        }
    }
}
