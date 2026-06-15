//
//  DeviceInformation.swift
//  HiddenBarIcons
//

import Foundation

/// Provides static device information that is queried once and cached.
enum DeviceInformation {
    /// The Mac model identifier (e.g., "MacBookPro18,1")
    static let modelIdentifier: String? = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "hw.model"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }()

    /// Returns true if the current Mac has a notch display
    static let hasNotch: Bool = {
        guard let model = modelIdentifier else { return false }

        // List of Mac models with notch displays
        // Source: https://support.apple.com/en-us/108052, https://support.apple.com/en-us/102869
        let notchedModels: Set<String> = [
            // MacBook Air 13" (M2-M5)
            "Mac14,2", "Mac15,12", "Mac16,12", "Mac17,3",
            // MacBook Air 15" (M2-M5)
            "Mac14,15", "Mac15,13", "Mac16,13", "Mac17,4",
            // MacBook Pro 14" (M1-M5)
            "MacBookPro18,3", "MacBookPro18,4",
            "Mac14,5", "Mac14,9",
            "Mac15,3", "Mac15,6", "Mac15,8", "Mac15,10",
            "Mac16,1", "Mac16,6", "Mac16,8",
            "Mac17,2", "Mac17,7", "Mac17,9",
            // MacBook Pro 16" (M1-M5)
            "MacBookPro18,1", "MacBookPro18,2",
            "Mac14,6", "Mac14,10",
            "Mac15,7", "Mac15,9", "Mac15,11",
            "Mac16,5", "Mac16,7",
            "Mac17,6", "Mac17,8",
        ]

        return notchedModels.contains(model)
    }()
}
