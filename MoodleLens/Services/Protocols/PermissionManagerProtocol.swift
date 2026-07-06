//
//  PermissionManagerProtocol.swift
//  MoodleLens
//
//  Created on 4/11/25.
//

import Foundation

/// Protocol for handling system permissions
protocol PermissionManagerProtocol: SelfResolvable {
    /// Types of permissions managed
    typealias PermissionType = PermissionManager.PermissionType
    
    /// Status of a permission
    typealias PermissionStatus = PermissionManager.PermissionStatus
    
    /// Checks screen capture permission status
    /// - Parameter completion: Callback with permission status
    func screenCapturePermissionStatus(completion: @escaping (PermissionStatus) -> Void)

    /// Requests screen capture permission
    /// - Parameter completion: Callback with permission result
    func requestScreenCapturePermission(completion: @escaping (Bool) -> Void)

    /// Best-effort reset of the app's TCC row for a permission before repair.
    func resetPermission(_ permissionType: PermissionType, completion: @escaping (Bool) -> Void)

    /// Opens the matching System Settings privacy pane.
    func openSystemSettings(for permissionType: PermissionType)
}
