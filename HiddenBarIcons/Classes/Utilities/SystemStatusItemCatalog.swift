//
//  SystemStatusItemCatalog.swift
//  HiddenBarIcons
//

import Foundation

/// Friendly names and SF Symbol icons for the system agents that own menu bar
/// extras. Their process names (SSMenuAgent, TextInputMenuAgent) and AX labels
/// ("Wi-Fi, connected, 3 bars") read like debugger output, and their bundles
/// carry generic icons — this catalog substitutes a human presentation.
/// Label keyword matching is English-only by design: an unrecognized label
/// degrades to its cleaned first component with the family's generic symbol.
enum SystemStatusItemCatalog {
    struct Entry {
        let displayName: String
        let symbolName: String?
    }

    static func entry(bundleIdentifier: String?, appName: String, label: String?) -> Entry? {
        switch bundleIdentifier {
        case "com.apple.controlcenter":
            return self.controlCenterEntry(label: label)
        case "com.apple.Spotlight":
            return Entry(displayName: String(localized: "Spotlight"), symbolName: "magnifyingglass")
        case "com.apple.TextInputMenuAgent":
            return Entry(displayName: String(localized: "Input Sources"), symbolName: "globe")
        default:
            if appName == "SSMenuAgent" || bundleIdentifier?.lowercased().contains("screensharing") == true {
                return Entry(displayName: String(localized: "Screen Sharing"), symbolName: "display")
            }
            return nil
        }
    }

    /// Labels that leak developer identifiers ("menuBarIcon",
    /// "circle.hexagongrid") are dropped: a human label contains whitespace,
    /// or has no dots and starts with an uppercase letter.
    static func humanReadableLabel(_ label: String?) -> String? {
        guard let label, !label.isEmpty else { return nil }
        if label.contains(where: \.isWhitespace) { return label }
        if label.contains(".") { return nil }
        if let first = label.first, first.isLowercase { return nil }
        return label
    }

    // MARK: - Control Center widgets

    /// The AX description carries state after the widget name
    /// ("Wi-Fi, connected, 3 bars") — the first comma component is the name.
    private static func controlCenterEntry(label: String?) -> Entry {
        let widget = label?
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !widget.isEmpty else {
            return Entry(displayName: String(localized: "Control Center"), symbolName: "switch.2")
        }
        return Entry(displayName: widget, symbolName: self.controlCenterSymbol(for: widget))
    }

    private static func controlCenterSymbol(for widget: String) -> String {
        let key = widget.lowercased()
        let keywordSymbols: [(String, String)] = [
            ("wi-fi", "wifi"),
            ("wifi", "wifi"),
            ("battery", "battery.100percent"),
            ("now playing", "play.circle"),
            ("clock", "clock"),
            ("sound", "speaker.wave.2"),
            ("volume", "speaker.wave.2"),
            ("focus", "moon"),
            ("do not disturb", "moon"),
            ("screen mirroring", "rectangle.on.rectangle"),
            ("display", "sun.max"),
            ("airdrop", "dot.radiowaves.left.and.right"),
            ("hotspot", "personalhotspot"),
            ("keyboard", "keyboard"),
            ("accessibility", "accessibility"),
            ("time machine", "clock.arrow.circlepath"),
            ("vpn", "lock.shield"),
            ("user", "person.crop.circle"),
            ("siri", "waveform"),
        ]
        for (keyword, symbol) in keywordSymbols where key.contains(keyword) {
            return symbol
        }
        return "switch.2"
    }
}
