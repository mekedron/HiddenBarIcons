//
//  HiddenAppMenuItemView.swift
//  HiddenBarIcons
//

import AppKit

@MainActor
final class HiddenAppMenuItemView: NSView {
    static let height: CGFloat = 24

    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false {
        didSet {
            if self.isHighlighted != oldValue {
                self.needsDisplay = true
                self.titleField.textColor = self.isHighlighted ? .selectedMenuItemTextColor : .labelColor
            }
        }
    }

    var onOpen: (@MainActor (HiddenAppOpenAction) -> Void)?

    override var isOpaque: Bool {
        false
    }

    init(title: String, icon: NSImage?, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        self.setupSubviews(title: title, icon: icon)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard self.isHighlighted else { return }

        let highlightRect = self.bounds.insetBy(dx: 5, dy: 1)
        let highlightPath = NSBezierPath(
            roundedRect: highlightRect,
            xRadius: 5,
            yRadius: 5
        )
        NSColor.selectedContentBackgroundColor.setFill()
        highlightPath.fill()
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

    override func mouseUp(with event: NSEvent) {
        let action: HiddenAppOpenAction = event.modifierFlags.contains(.option) ? .contextMenu : .primary
        self.open(action)
    }

    override func rightMouseUp(with _: NSEvent) {
        self.open(.contextMenu)
    }

    private func setupSubviews(title: String, icon: NSImage?) {
        self.imageView.image = icon
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.imageView)

        self.titleField.stringValue = title
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

    private func open(_ action: HiddenAppOpenAction) {
        let onOpen = self.onOpen
        self.enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            onOpen?(action)
        }
    }
}
