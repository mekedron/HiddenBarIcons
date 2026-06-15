//
//  StatusBarMockView.swift
//  HiddenBarIcons
//

import SwiftUI

private struct SeparatorPositionKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>?
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

struct StatusBarMockView: View {
    private var currentDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d  HH:mm"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            // Mock status bar
            HStack(spacing: 0) {
                Spacer()

                // Hidden items (left of separator)
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle")
                    Image(systemName: "scanner")
                    Image(systemName: "circle.square.fill")
                    Image(systemName: "lightswitch.on.square")
                }
                .foregroundStyle(.tertiary)

                // Separator (pipe)
                Image(nsImage: {
                    let image = NSImage(named: "separator") ?? NSImage()
                    image.isTemplate = true
                    return image
                }())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .anchorPreference(key: SeparatorPositionKey.self, value: .center) { $0 }

                // Arrow (collapse indicator)
                Image(nsImage: {
                    let image = NSImage(named: "collapse") ?? NSImage()
                    image.isTemplate = true
                    return image
                }())
                    .foregroundStyle(.primary)

                Spacer()
                    .frame(width: 16)

                // Shown items (right of arrow)
                HStack(spacing: 12) {
                    Image(systemName: "wifi")
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                    Text("75%")
                        .font(.system(size: 13))
                    Image(systemName: "battery.75")
                    Text(self.currentDateTime)
                        .font(.system(size: 13))
                }
                .foregroundStyle(.tertiary)
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .secondarySystemFill))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlayPreferenceValue(SeparatorPositionKey.self) { anchor in
                GeometryReader { geometry in
                    if let anchor {
                        HStack(spacing: 4) {
                            Text("Hidden")
                            Image(systemName: "arrow.up")
                            Text("Shown")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                        .position(x: geometry[anchor].x - 1, y: geometry.size.height + 16)
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }
}

#Preview {
    StatusBarMockView()
        .padding()
}
