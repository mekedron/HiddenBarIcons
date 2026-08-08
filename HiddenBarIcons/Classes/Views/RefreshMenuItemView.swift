//
//  RefreshMenuItemView.swift
//  HiddenBarIcons
//

import AppKit

/// Menu row for "Refresh hidden apps" that triggers a rescan WITHOUT closing
/// the menu: a custom view bypasses the menu-item action path, which is what
/// dismisses menu tracking, and the hidden-app rows update in place when the
/// scan lands (`MenuController.handleHiddenAppsCacheUpdated`).
@MainActor
final class RefreshMenuItemView: NSView {
    static let height: CGFloat = 24

    var onRefresh: (@MainActor () -> Void)?

    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: String(localized: "Refresh hidden apps"))
    private var trackingArea: NSTrackingArea?
    private var stuckResetTask: Task<Void, Never>?
    private(set) var isRefreshing = false

    private var isHighlighted = false {
        didSet {
            if self.isHighlighted != oldValue {
                self.needsDisplay = true
                self.applyTitleColor()
            }
        }
    }

    override var isOpaque: Bool {
        false
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        self.imageView.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        self.imageView.contentTintColor = .labelColor
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.imageView)

        self.titleField.font = NSFont.menuFont(ofSize: 0)
        self.titleField.lineBreakMode = .byTruncatingTail
        self.titleField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.titleField)

        NSLayoutConstraint.activate([
            self.imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
            self.imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.imageView.widthAnchor.constraint(equalToConstant: 16),
            self.imageView.heightAnchor.constraint(equalToConstant: 16),

            self.titleField.leadingAnchor.constraint(equalTo: self.imageView.trailingAnchor, constant: 8),
            self.titleField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14),
            self.titleField.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        stuckResetTask?.cancel()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard self.isHighlighted else { return }

        let highlightRect = self.bounds.insetBy(dx: 5, dy: 1)
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: 5, yRadius: 5).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            self.removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with _: NSEvent) {
        self.isHighlighted = true
    }

    override func mouseExited(with _: NSEvent) {
        self.isHighlighted = false
    }

    override func mouseUp(with _: NSEvent) {
        guard !self.isRefreshing else { return }
        self.setRefreshing(true)
        self.onRefresh?()
    }

    /// Toggles the transient "Refreshing…" look. The row unsticks itself after
    /// a few seconds in case no cache update ever lands (e.g. the scan was
    /// skipped because the status bar is expanded).
    func setRefreshing(_ refreshing: Bool) {
        guard refreshing != self.isRefreshing else { return }
        self.isRefreshing = refreshing
        self.titleField.stringValue = refreshing
            ? String(localized: "Refreshing…")
            : String(localized: "Refresh hidden apps")
        self.applyTitleColor()

        self.stuckResetTask?.cancel()
        if refreshing {
            self.stuckResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.setRefreshing(false)
            }
        }
    }

    private func applyTitleColor() {
        if self.isRefreshing {
            self.titleField.textColor = .secondaryLabelColor
        } else {
            self.titleField.textColor = self.isHighlighted ? .selectedMenuItemTextColor : .labelColor
        }
    }
}
