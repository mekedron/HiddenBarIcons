//
//  PreferencesView.swift
//  HiddenBarIcons
//

import Combine
import SwiftUI

struct PreferencesView: View {
    @AppStorage(PreferenceKeys.isAutoCollapseEnabled) private var isAutoCollapseEnabled = PreferenceDefaults
        .isAutoCollapseEnabled
    @AppStorage(PreferenceKeys.autoCollapseDelay) private var autoCollapseDelay = PreferenceDefaults.autoCollapseDelay
    @AppStorage(PreferenceKeys.showPreferencesOnLaunch) private var showPreferencesOnLaunch = PreferenceDefaults
        .showPreferencesOnLaunch
    @AppStorage(PreferenceKeys.isFullExpandEnabled) private var isFullExpandEnabled = PreferenceDefaults
        .isFullExpandEnabled
    @AppStorage(PreferenceKeys.showHiddenAppsInMenu) private var showHiddenAppsInMenu = PreferenceDefaults
        .showHiddenAppsInMenu
    @AppStorage(PreferenceKeys.allowRightClickHiddenApps) private var allowRightClickHiddenApps = PreferenceDefaults
        .allowRightClickHiddenApps
    @AppStorage(PreferenceKeys.hideSeparatorWhenExpanded) private var hideSeparatorWhenExpanded = PreferenceDefaults
        .hideSeparatorWhenExpanded

    // Login-item state is owned by the system (SMAppService), not @AppStorage.
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    @State private var isAccessibilityTrusted = AccessibilityManager.isTrusted()
    private let accessibilityPollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon and description
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "HiddenBarIcons is now running. Reorder status bar icons by \u{2318}-dragging. Drag icons to the left of the separator  |  to hide them."
                    )
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Right-click (or \u{2303}-click) the arrow icon to show the HiddenBarIcons menu.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Status bar mock
            StatusBarMockView()

            Spacer()

            // Auto-collapse duration
            HStack(spacing: 8) {
                Text("Auto-collapse after:")
                    .font(.system(size: 13))

                Picker("", selection: self.$autoCollapseDelay) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Spacer()
            }
            .padding(.bottom, 16)

            // Checkboxes
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable auto-collapse", isOn: self.$isAutoCollapseEnabled)
                    .font(.system(size: 13))

                Toggle("Fully expand status bar (shows Dock icon temporarily)", isOn: self.$isFullExpandEnabled)
                    .font(.system(size: 13))

                Toggle("Show this window when starting HiddenBarIcons", isOn: self.$showPreferencesOnLaunch)
                    .font(.system(size: 13))

                Toggle("Open at login", isOn: Binding(
                    get: { self.launchAtLogin.isEnabled },
                    set: { self.launchAtLogin.setEnabled($0) }
                ))
                .font(.system(size: 13))

                Toggle("Hide the separator pipe when expanded (hold \u{2318} to reveal it)", isOn: self.$hideSeparatorWhenExpanded)
                    .font(.system(size: 13))
                    .onChange(of: self.hideSeparatorWhenExpanded) { _, _ in
                        NotificationCenter.default.post(name: .separatorVisibilityPreferenceChanged, object: nil)
                    }
            }

            Divider()
                .padding(.vertical, 14)

            self.hiddenAppsSection

            Spacer()

            // Footer buttons
            HStack {
                Button(String(localized: "Quit")) {
                    NSApp.terminate(nil)
                }
                .controlSize(.large)

                Spacer()

                Button(String(localized: "Close")) {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(width: 640, height: 520)
        .onReceive(self.accessibilityPollTimer) { _ in
            self.isAccessibilityTrusted = AccessibilityManager.isTrusted()
            self.launchAtLogin.refresh()
        }
    }

    // MARK: - Hidden Apps Section

    @ViewBuilder
    private var hiddenAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show hidden apps in the context menu", isOn: self.$showHiddenAppsInMenu)
                .font(.system(size: 13))
                .onChange(of: self.showHiddenAppsInMenu) { _, isOn in
                    guard isOn else { return }
                    if !AccessibilityManager.isTrusted() {
                        AccessibilityManager.requestTrust()
                    }
                    NotificationCenter.default.post(name: .warmHiddenAppsCache, object: nil)
                }
                .onChange(of: self.isAccessibilityTrusted) { _, isTrusted in
                    if isTrusted, self.showHiddenAppsInMenu {
                        NotificationCenter.default.post(name: .warmHiddenAppsCache, object: nil)
                    }
                }

            Toggle("Allow right-clicking hidden apps in context menu", isOn: self.$allowRightClickHiddenApps)
                .font(.system(size: 13))
                .disabled(!self.showHiddenAppsInMenu)

            Text("When off, hold Option while choosing a hidden app to open its right-click menu.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)

            HStack(spacing: 8) {
                Text("Accessibility access:")
                    .font(.system(size: 13))
                Text(
                    self.isAccessibilityTrusted
                        ? String(localized: "Granted")
                        : String(localized: "Not granted")
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.isAccessibilityTrusted ? Color.green : Color.red)

                Spacer()

                Button(String(localized: "Open Settings…")) {
                    self.isAccessibilityTrusted = AccessibilityManager.requestTrust()
                    AccessibilityManager.openSettings()
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}

#Preview {
    PreferencesView()
}
