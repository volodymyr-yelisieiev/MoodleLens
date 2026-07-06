//
//  AccessibilityPermissions.swift
//  MoodleLens
//
//  Created on 4/10/25.
//

import Cocoa

/// A helper class to check and request accessibility permissions
/// which are required for global hotkeys and screen recording features
class AccessibilityPermissions {
    /// Checks if the application has accessibility permissions
    static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        return accessibilityEnabled
    }

    /// Triggers the native macOS prompt when explicitly requested by the user.
    static func requestAccessibilityPermissions() {
        guard !checkAccessibilityPermissions(prompt: true),
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
