//
//  MoodleLensApp.swift
//  MoodleLens
//
//  Created by Maxim Frolov on 4/8/25.
//  Global shortcuts are user-customizable from Settings.
//

import SwiftUI
import AppKit
import Cocoa
import ScreenCaptureKit

#if canImport(Sparkle)
import Sparkle
#endif

@main
struct MoodleLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        DIRegistrar.configure()
        
        // Register app delegate after it's created by SwiftUI
        // This works because @NSApplicationDelegateAdaptor initializes the delegate
        // before the App struct's init() is called
        DIContainer.shared.registerSingleton(AppDelegateProtocol.self, instance: appDelegate)
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        settingsWindow = nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, AppDelegateProtocol {
    // Dependencies - injected through initializer
    private let windowManager: WindowManagerProtocol
    private let openAIClient: OpenAIClientProtocol
    private let screenshotService: ScreenshotServiceProtocol
    private let permissionManager: PermissionManagerProtocol
    private let notificationService: NotificationServiceProtocol
    private let viewFactory: ViewFactory
    
    // Other variables
    private var keyEventMonitor: Any?
    private var globalHotkeyManager = GlobalHotkeyManager.shared
    private var settingsWindow: NSWindow?

    #if canImport(Sparkle)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif
    
    // Primary initializer with dependencies
    init(windowManager: WindowManagerProtocol,
         openAIClient: OpenAIClientProtocol,
         screenshotService: ScreenshotServiceProtocol,
         permissionManager: PermissionManagerProtocol,
         notificationService: NotificationServiceProtocol,
         viewFactory: ViewFactory) {
        
        self.windowManager = windowManager
        self.openAIClient = openAIClient
        self.screenshotService = screenshotService
        self.permissionManager = permissionManager
        self.notificationService = notificationService
        self.viewFactory = viewFactory
        
        super.init()
    }
    
    // Convenience initializer for SwiftUI integration with @NSApplicationDelegateAdaptor
    convenience override init() {
        // Safely resolve dependencies from container with better error handling
        guard let windowManager = DIContainer.shared.resolve(WindowManagerProtocol.self) else {
            fatalError("Failed to resolve WindowManagerProtocol")
        }
        guard let openAIClient = DIContainer.shared.resolve(OpenAIClientProtocol.self) else {
            fatalError("Failed to resolve OpenAIClientProtocol")
        }
        guard let screenshotService = DIContainer.shared.resolve(ScreenshotServiceProtocol.self) else {
            fatalError("Failed to resolve ScreenshotServiceProtocol")
        }
        guard let permissionManager = DIContainer.shared.resolve(PermissionManagerProtocol.self) else {
            fatalError("Failed to resolve PermissionManagerProtocol")
        }
        guard let notificationService = DIContainer.shared.resolve(NotificationServiceProtocol.self) else {
            fatalError("Failed to resolve NotificationServiceProtocol")
        }
        
        let viewFactory = DIRegistrar.createViewFactory()
        
        self.init(
            windowManager: windowManager,
            openAIClient: openAIClient,
            screenshotService: screenshotService,
            permissionManager: permissionManager,
            notificationService: notificationService,
            viewFactory: viewFactory
        )
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Allow app to be interactive and appear in dock for better keyboard handling
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = true
        
        // Use .accessory to hide app from dock while maintaining functionality
        NSApp.setActivationPolicy(.accessory)
        
        // Setup direct reference to app delegate in ScreenshotService
        screenshotService.setAppDelegate(self)

        #if canImport(Sparkle)
        _ = updaterController
        #endif

        BrowserContextProvider.startTrackingFrontmostBrowser()
        
        // Set up global key event monitoring
        setupKeyEventMonitoring()
        
        // Register global hotkeys that work system-wide even when app doesn't have focus
        globalHotkeyManager.registerHotkeys()

        if Self.shouldShowSettingsOnLaunch(openAIClient: openAIClient) {
            showSettings(firstRunSetup: true)
        }
    }

    static func shouldShowSettingsOnLaunch(openAIClient: OpenAIClientProtocol) -> Bool {
        !openAIClient.isConfigured()
    }
    
    private func setupKeyEventMonitoring() {
        // Using both local and global event monitors for reliable key detection
        // User-customizable hotkeys are handled through AppHotkey bindings.
        
        // Set up a local monitor to catch key events within our own app
        // This works even when text fields have focus
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            if self.handleAppHotkey(event) {
                return nil
            }

            if self.handleAppCommand(event) {
                return nil
            }
            
            // Let other key events pass through
            return event
        }
        
        // Store the local monitor
        self.keyEventMonitor = localMonitor
        
        // Carbon handles system-wide hotkeys. A second NSEvent global monitor can double-fire toggles.
    }

    private func handleAppCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags.contains(.command) &&
            !flags.contains(.option) &&
            !flags.contains(.control) &&
            !flags.contains(.shift) &&
            !flags.contains(.function)

        if commandOnly && event.keyCode == 12 {
            quitApp()
            return true
        }

        if commandOnly && event.keyCode == 13 {
            closeKeyWindow()
            return true
        }

        if event.keyCode == 53,
           let settingsWindow,
           NSApp.keyWindow === settingsWindow {
            closeSettingsWindow()
            return true
        }

        return false
    }
    
    // Helper method to handle app hotkeys
    @discardableResult
    private func handleAppHotkey(_ event: NSEvent) -> Bool {
        guard let hotkey = AppHotkey.matching(event) else { return false }

        switch hotkey {
            case .openSettings:
                DispatchQueue.main.async {
                    self.showSettings()
                }
                return true

            case .ask:
                DispatchQueue.main.async {
                    AskController.shared.ask()
                }
                return true

            case .toggleBubble:
                DispatchQueue.main.async {
                    AskController.shared.toggleBubble()
                }
                return true

            case .clearChat:
                DispatchQueue.main.async {
                    AskController.shared.clearHistory()
                }
                return true
        }
    }
    
    // Helper to check if the app is currently editing text
    private func isCurrentlyEditingText() -> Bool {
        if let window = NSApplication.shared.keyWindow {
            let firstResponder = window.firstResponder
            return firstResponder is NSTextField || firstResponder is NSTextView
        }
        return false
    }
    
    @objc func showSettings() {
        showSettings(firstRunSetup: false)
    }

    func showSettings(firstRunSetup: Bool) {
        if let settingsWindow, settingsWindow.isVisible {
            if Self.shouldCloseSettingsWindow(isKeyWindow: settingsWindow.isKeyWindow) {
                closeSettingsWindow()
            } else {
                focusSettingsWindow(settingsWindow)
            }
            return
        }

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: firstRunSetup ? 620 : 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.delegate = self
        settingsWindow.backgroundColor = .windowBackgroundColor
        settingsWindow.isOpaque = true

        let hostingView = NSHostingView(
            rootView: SettingsView(isFirstRunSetup: firstRunSetup) { [weak self] in
                if firstRunSetup {
                    self?.closeSettingsWindow()
                }
            }
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        settingsWindow.contentView = hostingView
        settingsWindow.secure()

        settingsWindow.center()
        settingsWindow.title = "Settings"
        settingsWindow.minSize = NSSize(width: 520, height: 520)
        settingsWindow.level = .normal
        self.settingsWindow = settingsWindow
        ArrowCursorLock.install()
        ArrowCursorLock.apply(to: settingsWindow)
        focusSettingsWindow(settingsWindow)
    }

    static func shouldCloseSettingsWindow(isKeyWindow: Bool) -> Bool {
        isKeyWindow
    }

    private func focusSettingsWindow(_ settingsWindow: NSWindow) {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleWindowVisibility() {
        showSettings()
    }
    
    /// Check if the window is currently hidden
    func isWindowHidden() -> Bool {
        !(windowManager.window?.isVisible ?? false)
    }
    
    /// Explicitly hide the window
    func hideWindow() {
        windowManager.hideWindow()
    }

    func printPrivacyDiagnostics() {
        guard let window = windowManager.window else {
            print("Privacy diagnostics: window=missing activationPolicy=\(activationPolicyName(NSApp.activationPolicy()))")
            return
        }

        let behaviors = window.collectionBehavior
        print("Privacy diagnostics: activationPolicy=\(activationPolicyName(NSApp.activationPolicy())) sharingType=\(window.sharingType.rawValue) level=\(window.level.rawValue) excludedFromWindowsMenu=\(window.isExcludedFromWindowsMenu) transient=\(behaviors.contains(.transient)) ignoresCycle=\(behaviors.contains(.ignoresCycle)) canJoinAllSpaces=\(behaviors.contains(.canJoinAllSpaces))")
    }

    private func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }
    
    /// Explicitly show the window (used by screenshot service)
    func restoreWindow() {
        showSettings()
    }

    private func closeKeyWindow() {
        if let settingsWindow, NSApp.keyWindow === settingsWindow {
            closeSettingsWindow()
        } else if NSApp.keyWindow === windowManager.window {
            hideWindow()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    private func closeSettingsWindow() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        #else
        if let url = URL(string: "https://github.com/volodymyr-yelisieiev/MoodleLens/releases") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
    
    /// Capture a screenshot and send it to OpenAI
    @objc func captureScreenshot(_ notification: Notification? = nil) {
        // Get context info from notification if available
        var contextInfo: [String: Any]?
        if let notificationObject = notification?.object as? [String: Any] {
            contextInfo = notificationObject
        }
        contextInfo = BrowserContextProvider.addCurrentContext(to: contextInfo)
        
        // Check if we have an API key first
        if contextInfo?["deferAnalysis"] as? Bool != true && !openAIClient.hasApiKey {
            // Show error as notification
            notificationService.post(
                name: .openaiError, // Use the correct notification name (lowercase 'i')
                object: ["error": "OpenAI API key is missing. Open Settings and paste a valid key."]
            )
            
            // Open settings window to prompt for API key
            DispatchQueue.main.async {
                self.showSettings()
            }
            return
        }
        
        // Broadcast that we're starting the screenshot process
        notificationService.post(name: .screenshotProcessing, object: contextInfo)
        
        // First check if we have screen capture permission
        permissionManager.screenCapturePermissionStatus { [weak self] status in
            guard let self = self else { return }
            
            if status == .authorized {
                // Execute the screenshot capture on the main thread
                DispatchQueue.main.async {
                    _ = self.screenshotService.captureScreenshot(contextInfo: contextInfo)
                }
            } else {
                DispatchQueue.main.async {
                    self.notificationService.post(
                        name: .screenshotError,
                        object: ["error": "Screen Recording permission is required. Open Settings and use Grant / Repair."]
                    )
                }
            }
        }
    }
    
    @objc func quitApp() {
        // Stop monitoring key events
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Unregister global hotkeys
        globalHotkeyManager.unregisterHotkeys()
        
        // Clean up temporary files before exit
        TempFileManager.shared.cleanupAllTempFiles()
        
        NSApplication.shared.terminate(nil)
    }
    
    /// Clean up all temporary files
    func cleanupTempFiles() {
        // Use TempFileManager to clean up all temporary files
        let deletedCount = TempFileManager.shared.cleanupAllTempFiles()
        
        // Show confirmation dialog
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Cleanup Complete"
            alert.informativeText = "Deleted \(deletedCount) temporary files."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    /// Clear chat history
    @objc func clearChatHistory() {
        AskController.shared.clearHistory()
    }
    
    // Application lifecycle events
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure hotkeys are unregistered
        globalHotkeyManager.unregisterHotkeys()
        TempFileManager.shared.cleanupAllTempFiles()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            restoreWindow()
        }
        return true
    }
    
    func applicationWillResignActive(_ notification: Notification) {
        // No need to unregister hotkeys when app goes to background
        // as we want them to work system-wide
    }
    
    deinit {
        // Clean up event monitor
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Unregister hotkeys
        globalHotkeyManager.unregisterHotkeys()
        
        // Remove notification observers
        notificationService.removeObserver(self)
    }
}
