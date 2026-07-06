//
//  NotificationManager.swift
//  MoodleLens
//
//  Created on 4/9/25.
//

import Foundation

/// NotificationManager centralizes all notification definitions and provides
/// convenience methods for posting and observing notifications.
class NotificationManager {
    /// Singleton instance
    static let shared = NotificationManager()
    
    // Private initializer for singleton
    private init() {}
    
    // MARK: - Notification Names
    
    /// Namespace for all notification names used in the application.
    /// This ensures all notifications are defined in one place and prevents duplications.
    struct Names {
        // MARK: - User Interface Notifications
        
        /// Posted when a key press is detected
        static let keyPressDetected = Notification.Name("KeyPressDetected")
        
        /// Posted when text field focus state changes
        static let textFieldFocusChanged = Notification.Name("TextFieldFocusChanged")
        
        /// Posted to request focusing a text field
        static let focusTextFieldRequested = Notification.Name("FocusTextFieldRequested")
        
        // MARK: - OpenAI Notifications
        
        /// Posted when a response is received from OpenAI
        static let openAIResponseReceived = Notification.Name("OpenAIResponseReceived")
        
        /// Posted when an error occurs with OpenAI
        static let openAIError = Notification.Name("OpenAIError")
        
        // MARK: - Permission Notifications
        
        /// Posted when permission status changes
        static let permissionStatusChanged = Notification.Name("PermissionStatusChanged")
        
        // MARK: - Window Notifications
        
        /// Posted when window visibility should be toggled
        static let windowVisibilityToggle = Notification.Name("WindowVisibilityToggle")

        /// Posted when a global hotkey cannot be registered
        static let hotkeyRegistrationFailed = Notification.Name("HotkeyRegistrationFailed")
        
        // MARK: - Screenshot Notifications
        
        /// Posted when a screenshot is captured
        static let screenshotCaptured = Notification.Name("ScreenshotCaptured")
        
        /// Posted when there's an error during screenshot capture or processing
        static let screenshotError = Notification.Name("ScreenshotError")
        
        /// Posted when a screenshot is being processed
        static let screenshotProcessing = Notification.Name("ScreenshotProcessing")
        
        /// Posted to request a screenshot capture
        static let captureScreenshotRequested = Notification.Name("CaptureScreenshotRequested")
    }
    
    // MARK: - Convenience Methods for Posting Notifications
    
    /// Post a notification for a key press
    /// - Parameter key: The key that was pressed
    func postKeyPress(key: String) {
        NotificationCenter.default.post(
            name: Names.keyPressDetected,
            object: ["key": key]
        )
    }
    
    /// Post a notification that text field focus has changed
    /// - Parameter focused: Whether the text field is focused
    func postTextFieldFocusChanged(focused: Bool) {
        NotificationCenter.default.post(
            name: Names.textFieldFocusChanged,
            object: ["focused": focused]
        )
    }
    
    /// Post a notification to request focusing a text field
    func postFocusTextFieldRequest() {
        NotificationCenter.default.post(name: Names.focusTextFieldRequested, object: nil)
    }
    
    /// Post a notification with an OpenAI response
    /// - Parameter response: The response from OpenAI
    func postOpenAIResponse(response: String) {
        NotificationCenter.default.post(
            name: Names.openAIResponseReceived,
            object: ["response": response]
        )
    }
    
    /// Post a notification with an OpenAI error
    /// - Parameter error: The error message
    func postOpenAIError(error: String) {
        NotificationCenter.default.post(
            name: Names.openAIError,
            object: ["error": error]
        )
    }
    
    /// Post a notification that permission status has changed
    /// - Parameters:
    ///   - type: The type of permission
    ///   - granted: Whether the permission was granted
    func postPermissionStatusChanged(type: String, granted: Bool) {
        NotificationCenter.default.post(
            name: Names.permissionStatusChanged,
            object: ["type": type, "granted": granted]
        )
    }
    
    /// Post a notification to toggle window visibility
    func postWindowVisibilityToggle() {
        NotificationCenter.default.post(name: Names.windowVisibilityToggle, object: nil)
    }
    
    /// Post a notification that a screenshot was captured
    /// - Parameter path: Path to the saved screenshot
    func postScreenshotCaptured(path: String) {
        NotificationCenter.default.post(
            name: Names.screenshotCaptured,
            object: ["path": path]
        )
    }
    
    /// Post a notification that there was an error with screenshot processing
    /// - Parameter error: The error message
    func postScreenshotError(error: String) {
        NotificationCenter.default.post(
            name: Names.screenshotError,
            object: ["error": error]
        )
    }
    
    /// Post a notification that screenshot processing has started
    func postScreenshotProcessing() {
        NotificationCenter.default.post(name: Names.screenshotProcessing, object: nil)
    }
    
    /// Post a notification to request a screenshot capture
    func requestScreenshotCapture() {
        NotificationCenter.default.post(name: Names.captureScreenshotRequested, object: nil)
    }
    
    // MARK: - Convenience Methods for Observing Notifications
    
    /// Observe a notification with a closure
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - object: The object posting the notification (optional)
    ///   - queue: The operation queue for the handler (default is main)
    ///   - handler: The closure to call when the notification is received
    /// - Returns: An observer token that can be used to stop observing
    @discardableResult
    func observe(
        name: Notification.Name,
        object: Any? = nil,
        queue: OperationQueue = .main,
        handler: @escaping (Notification) -> Void
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: queue,
            using: handler
        )
    }
    
    /// Stop observing a notification
    /// - Parameter observer: The observer token returned by observe()
    func stopObserving(_ observer: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(observer)
    }
    
    /// Stop observing all notifications for a given object
    /// - Parameter object: The object to stop observing
    func stopObserving(object: Any) {
        NotificationCenter.default.removeObserver(object)
    }
}

// MARK: - Notification Names

/// Extension to support direct access to notification names
extension Notification.Name {
    // User Interface
    static let keyPressNotification = NotificationManager.Names.keyPressDetected
    static let textFieldFocusChanged = NotificationManager.Names.textFieldFocusChanged
    static let focusTextFieldNotification = NotificationManager.Names.focusTextFieldRequested
    
    // OpenAI
    static let openAIResponseReceived = NotificationManager.Names.openAIResponseReceived
    static let openaiError = NotificationManager.Names.openAIError
    
    // Window
    static let windowVisibilityToggle = NotificationManager.Names.windowVisibilityToggle
    static let hotkeyRegistrationFailed = NotificationManager.Names.hotkeyRegistrationFailed
    
    // Screenshot
    static let captureScreenshotRequested = NotificationManager.Names.captureScreenshotRequested
    static let screenshotCaptured = NotificationManager.Names.screenshotCaptured
    static let screenshotError = NotificationManager.Names.screenshotError
    static let screenshotProcessing = NotificationManager.Names.screenshotProcessing
}
