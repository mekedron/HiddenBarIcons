//
//  main.swift
//  HiddenBarIcons
//

import Cocoa

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
