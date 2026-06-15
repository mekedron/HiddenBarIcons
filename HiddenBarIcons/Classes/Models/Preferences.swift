//
//  Preferences.swift
//  HiddenBarIcons
//

import Foundation

enum PreferenceKeys {
    static let isAutoCollapseEnabled = "isAutoCollapseEnabled"
    static let autoCollapseDelay = "autoCollapseDelay"
    static let showPreferencesOnLaunch = "showPreferencesOnLaunch"
    static let isFullExpandEnabled = "isFullExpandEnabled"
    static let showHiddenAppsInMenu = "showHiddenAppsInMenu"
    static let allowRightClickHiddenApps = "allowRightClickHiddenApps"
    static let hideSeparatorWhenExpanded = "hideSeparatorWhenExpanded"
}

enum PreferenceDefaults {
    static let isAutoCollapseEnabled = true
    static let autoCollapseDelay = 10 // seconds
    static let showPreferencesOnLaunch = true
    static let isFullExpandEnabled = true
    static let showHiddenAppsInMenu = true
    static let allowRightClickHiddenApps = true
    static let hideSeparatorWhenExpanded = false
}
