//
//  PermissionManager.swift
//  MoodleLens
//
//  Created on 4/9/25.
//  Updated for better screen capture permission handling
//

import Foundation
import AppKit
import Cocoa

/// A centralized manager for handling all permission requests in the application.
/// This eliminates scattered permission handling code across multiple files.
class PermissionManager: PermissionManagerProtocol {
    // Singleton instance
    static let shared = PermissionManager()

    // Use the centralized notification name from NotificationManager
    // This class is itself a centralized manager, so we'll keep our own constant
    // but make sure it matches the one in NotificationManager
    static let permissionStatusChanged = NotificationManager.Names.permissionStatusChanged

    // Dependencies
    private let notificationService: NotificationServiceProtocol

    // Initialize with dependencies
    init(notificationService: NotificationServiceProtocol) {
        self.notificationService = notificationService
    }

    // Convenience initializer for singleton during transition to DI
    private convenience init() {
        // During transition, fallback to default notification service
        let notificationService = DIContainer.shared.resolve(NotificationServiceProtocol.self) ?? DefaultNotificationService()
        self.init(notificationService: notificationService)
    }

    // MARK: - Permission Status

    /// Represents the current status of a permission
    enum PermissionStatus {
        case notDetermined
        case denied
        case restricted
        case authorized
        case unknown
    }

    /// Types of permissions managed by this class
    enum PermissionType: String, Hashable {
        case screenCapture
        case accessibility
    }

    // MARK: - Current Status Checking

    /// Check the current status of screen capture permission
    func screenCapturePermissionStatus(completion: @escaping (PermissionStatus) -> Void) {
        DispatchQueue.main.async {
            completion(CGPreflightScreenCaptureAccess() ? .authorized : .denied)
        }
    }

    // MARK: - Permission Requests

    /// Request screen capture permission
    /// - Parameter completion: Callback with result of the permission request
    func requestScreenCapturePermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let granted = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
            self.notificationService.post(
                name: Self.permissionStatusChanged,
                object: ["type": PermissionType.screenCapture.rawValue, "granted": granted]
            )
            completion(granted)
        }
    }

    func resetPermission(_ permissionType: PermissionType, completion: @escaping (Bool) -> Void) {
        let service: String
        switch permissionType {
        case .screenCapture:
            service = "ScreenCapture"
        case .accessibility:
            service = "Accessibility"
        }

        TCCPermissionResetter.reset(service: service, completion: completion)
    }

    // MARK: - Helper Methods

    /// Open system settings for the specific permission type
    /// - Parameter permissionType: Type of permission to open settings for
    func openSystemSettings(for permissionType: PermissionType) {
        DispatchQueue.main.async {
            let urlString: String

            switch permissionType {
            case .screenCapture:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            case .accessibility:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            }

            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
