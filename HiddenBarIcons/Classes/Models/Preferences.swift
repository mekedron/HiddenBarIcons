//
//  Preferences.swift
//  HiddenBarIcons
//

import Foundation

enum PreferenceKeys {
    static let isAutoCollapseEnabled = "isAutoCollapseEnabled"
    static let autoCollapseDelay = "autoCollapseDelay"
    static let showPreferencesOnLaunch = "showPreferencesOnLaunch"
    static let hidePreferencesOnLoginLaunch = "hidePreferencesOnLoginLaunch"
    static let isFullExpandEnabled = "isFullExpandEnabled"
    static let showHiddenAppsInMenu = "showHiddenAppsInMenu"
    static let showAllAppsInMenu = "showAllAppsInMenu"
    static let allowRightClickHiddenApps = "allowRightClickHiddenApps"
    static let hideSeparatorWhenExpanded = "hideSeparatorWhenExpanded"
    static let isMenuOnlyModeEnabled = "isMenuOnlyModeEnabled"
}

enum PreferenceDefaults {
    static let isAutoCollapseEnabled = true
    static let autoCollapseDelay = 10 // seconds
    static let showPreferencesOnLaunch = true
    static let hidePreferencesOnLoginLaunch = true
    static let isFullExpandEnabled = true
    static let showHiddenAppsInMenu = true
    static let showAllAppsInMenu = false
    static let allowRightClickHiddenApps = true
    static let hideSeparatorWhenExpanded = false
    static let isMenuOnlyModeEnabled = false
}
