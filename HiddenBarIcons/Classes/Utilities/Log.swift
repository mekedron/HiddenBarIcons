//
//  Log.swift
//  HiddenBarIcons
//
//  Lightweight logging shim that replaces DZFoundation's `DZLog`, so the
//  ported sources keep their existing call sites without depending on a
//  third-party package. Backed by the unified logging system (os.Logger).
//

import Foundation
import os

private let hbiLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.mekedron.HiddenBarIcons",
    category: "HiddenBarIcons"
)

/// Drop-in replacement for DZFoundation's `DZLog`, backed by the unified
/// logging system. Emitted at the `debug` level, so it stays out of the way
/// in normal use but is available when debug logging is enabled for the
/// subsystem (e.g. via Console.app or `log stream`).
func DZLog(_ message: String) {
    hbiLogger.debug("\(message, privacy: .public)")
}
