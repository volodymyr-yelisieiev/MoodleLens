//
//  AppDelegateProtocol.swift
//  MoodleLens
//
//  Created on 4/11/25.
//

import Foundation
import AppKit

/// Protocol defining the public interface of the AppDelegate
/// This allows for better testability and dependency management
protocol AppDelegateProtocol: AnyObject {
    /// Print privacy/window diagnostics without user content
    func printPrivacyDiagnostics()

    /// Shows settings window
    func showSettings()

    /// Shows settings window, optionally in first-run setup mode
    func showSettings(firstRunSetup: Bool)

    /// Open the native updater UI
    func checkForUpdates()
    
    /// Quit the application
    func quitApp()
    
}
