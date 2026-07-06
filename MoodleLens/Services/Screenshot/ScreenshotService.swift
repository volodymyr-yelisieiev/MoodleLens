//
//  ScreenshotService.swift
//  MoodleLens
//
//  Created on 4/10/25.
//

import Cocoa
import Foundation
import ScreenCaptureKit
import SwiftUI

/// A service that handles capturing screenshots and sending them to OpenAI for processing
class ScreenshotService: NSObject, ScreenshotServiceProtocol {
    // Singleton instance
    static let shared = ScreenshotService()
    static let screenshotScopeKey = "screenshotScope"
    static let screenshotScopeDisplayViewport = "display_viewport"
    
    // Dependencies
    private let openAIClient: OpenAIClientProtocol
    private let notificationService: NotificationServiceProtocol
    private let permissionManager: PermissionManagerProtocol
    
    // Initialize with dependencies
    init(openAIClient: OpenAIClientProtocol, notificationService: NotificationServiceProtocol, permissionManager: PermissionManagerProtocol) {
        self.openAIClient = openAIClient
        self.notificationService = notificationService
        self.permissionManager = permissionManager
        super.init()
    }
    
    // Convenience initializer for singleton during transition to DI
    private convenience override init() {
        // During transition, fallback to shared instances
        let openAIClient = DIContainer.shared.resolve(OpenAIClientProtocol.self) ?? OpenAIClient.shared
        let notificationService = DIContainer.shared.resolve(NotificationServiceProtocol.self) ?? DefaultNotificationService()
        let permissionManager = DIContainer.shared.resolve(PermissionManagerProtocol.self) ?? PermissionManager.shared
        
        self.init(openAIClient: openAIClient, notificationService: notificationService, permissionManager: permissionManager)
    }
    
    func setAppDelegate(_: AppDelegateProtocol) {}
    
    // MARK: - Screenshot States and Notifications
    
    /// Notification names for screenshot-related events
    enum Notifications {
        static let screenshotCaptured = Notification.Name("ScreenshotCaptured")
        static let screenshotError = Notification.Name("ScreenshotError")
        static let screenshotProcessing = Notification.Name("ScreenshotProcessing")
    }
    
    // MARK: - Screenshot Methods
    
    /// Store context information for the screenshot
    private var currentContextInfo: [String: Any]?
    
    /// Set context information for the screenshot
    /// - Parameter contextInfo: Dictionary of context information
    func setContextInfo(_ contextInfo: [String: Any]?) {
        self.currentContextInfo = contextInfo
    }

    func analyzeScreenshot(at imageURL: URL, prompt: String, contextInfo: [String: Any]? = nil) {
        sendToOpenAI(imageURL: imageURL, prompt: prompt, contextInfo: contextInfo)
    }
    
    /// Take a screenshot of the screen.
    /// - Returns: Boolean indicating success
    func captureScreenshot(contextInfo: [String: Any]? = nil) -> Bool {
        
        
        // If contextInfo is provided, store it
        if let contextInfo = contextInfo {
            setContextInfo(contextInfo)
        }
        
        // This method must be called on the main thread
        assert(Thread.isMainThread, "captureScreenshot must be called on the main thread")
        
        if contextInfo?["source"] as? String != AskController.source {
            notificationService.post(
                name: Notifications.screenshotProcessing,
                object: contextInfo
            )
        }

        Task { [weak self] in
            guard let self else { return }
            let finalImage = await self.captureScreen()

            await MainActor.run {
                if let finalImage {
                    self.processScreenshot(finalImage)
                } else {
                    self.postScreenshotError("Could not capture a screenshot. Enable MoodleLens in System Settings → Privacy & Security → Screen Recording, then try again.")
                }
            }
        }

        return true
    }
    
    /// Capture the entire screen silently.
    /// - Returns: NSImage if successful, nil otherwise
    private func captureScreen() async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }

            let bundleID = Bundle.main.bundleIdentifier
            let appWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == bundleID
            }
            let filter = SCContentFilter(display: display, excludingWindows: appWindows)
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = false

            let image = try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                    if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "ScreenshotService", code: 1))
                    }
                }
            }

            return NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        } catch {
            print("ScreenCaptureKit screenshot failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Process a screenshot by saving it and sending to OpenAI
    /// - Parameter screenshot: The screenshot to process
    func processScreenshot(_ screenshot: NSImage) {
        // Use TempFileManager to create and track a temporary file
        let tempURL = TempFileManager.shared.createTempFileURL(prefix: "Screenshot", extension: "png")
        var handedToOpenAI = false
        defer {
            if !handedToOpenAI {
                TempFileManager.shared.deleteTempFile(tempURL)
            }
        }
        
        // Save image to file
        guard let tiffData = screenshot.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData),
              let pngData = imageRep.representation(using: .png, properties: [:]) else {
            postScreenshotError("Could not prepare the screenshot image. Try capturing again.")
            currentContextInfo = nil
            return
        }
        
        do {
            try pngData.write(to: tempURL)
            
            // Notify about captured screenshot with path
            let contextInfo = currentContextInfo
            let shouldDeferAnalysis = contextInfo?["deferAnalysis"] as? Bool == true
            let prompt = contextInfo?["prompt"] as? String

            DispatchQueue.main.async {
                var notificationData: [String: Any] = ["path": tempURL.path]
                
                // Add context info if available
                if let contextInfo {
                    for (key, value) in contextInfo {
                        notificationData[key] = value
                    }
                }
                notificationData[Self.screenshotScopeKey] = Self.screenshotScopeDisplayViewport
                
                self.notificationService.post(
                    name: Self.Notifications.screenshotCaptured,
                    object: notificationData
                )
            }

            if shouldDeferAnalysis {
                handedToOpenAI = true
                currentContextInfo = nil
                return
            }
            
            // Send to OpenAI
            sendToOpenAI(imageURL: tempURL, prompt: prompt, contextInfo: currentContextInfo)
            handedToOpenAI = true
            
            // Clear context info after sending
            currentContextInfo = nil
        } catch {
            postScreenshotError("Could not save the screenshot for analysis: \(error.localizedDescription). Check disk space and try again.")
            currentContextInfo = nil
        }
    }
    
    /// Send the screenshot to OpenAI for processing
    /// - Parameters:
    ///   - imageURL: The URL of the image file
    ///   - contextInfo: Optional context information for replied messages
    private func sendToOpenAI(imageURL: URL, prompt requestedPrompt: String? = nil, contextInfo: [String: Any]? = nil) {
        // Notify that processing has begun
        DispatchQueue.main.async {
            self.notificationService.post(
                name: Self.Notifications.screenshotProcessing,
                object: contextInfo
            )
        }
        
        let defaultPrompt = "Analyze this image. If it contains code or a programming problem, provide a complete, working solution with explanations and optimal time/space complexity. If it's a coding problem like LeetCode or similar, provide the full solution code, not just a description."
        var prompt = requestedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultPrompt
        if prompt.isEmpty {
            prompt = defaultPrompt
        }
        
        // If we have context info, add a note about it
        if contextInfo != nil && (contextInfo?["replyChain"] as? [UUID])?.isEmpty == false {
            prompt = "Analyze this image in response to the previous conversation. \(prompt)"
        }
        if let browserContext = contextInfo?[BrowserContextProvider.contextInfoKey] as? String,
           !browserContext.isEmpty {
            prompt += "\n\nUse this browser DOM context as supporting evidence when it helps. It may include controls or options not visible in the screenshot:\n\(browserContext)"
        }
        
        // Send to OpenAI via the OpenAIClient - this is network operation so it's ok on background
        openAIClient.sendImageRequest(
            imageURL: imageURL, 
            prompt: prompt,
            contextInfo: contextInfo
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                print("Successfully processed image with OpenAI")
                
                // The response is already handled via notification in OpenAIClient
                
                // Clean up the temporary screenshot file
                DispatchQueue.global(qos: .background).async {
                    TempFileManager.shared.deleteTempFile(imageURL)
                }
                
            case .failure(let error):
                self.postScreenshotError("Error processing image: \(error.localizedDescription)")
                
                // Clean up the temporary screenshot file even on error
                DispatchQueue.global(qos: .background).async {
                    TempFileManager.shared.deleteTempFile(imageURL)
                }
            }
        }
    }
    
    /// Post an error notification
    /// - Parameter message: The error message
    private func postScreenshotError(_ message: String) {
        var payload: [String: Any] = ["error": message]
        if let contextInfo = currentContextInfo {
            for (key, value) in contextInfo {
                payload[key] = value
            }
        }

        DispatchQueue.main.async {
            self.notificationService.post(
                name: Self.Notifications.screenshotError,
                object: payload
            )
        }
    }
    
}

// Import extension for TempFileManager
extension ScreenshotService {
    // Make TempFileManager available to ScreenshotService
    var tempFileManager: TempFileManager {
        return TempFileManager.shared
    }
}
