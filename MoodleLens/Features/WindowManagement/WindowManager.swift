//
//  WindowManager.swift
//  MoodleLens
//
//  Created by Maxim Frolov on 4/8/25.
//

import SwiftUI
import AppKit
import Cocoa

private final class HiddenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resetCursorRects() {}
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

enum ArrowCursorLock {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .cursorUpdate
        ]) { event in
            if let window = event.window, NSApp.windows.contains(window) {
                forceArrow()
            }
            return event
        }
    }

    static func apply(to window: NSWindow?) {
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        window.disableCursorRects()
        discardCursorRects(in: window.contentView)
        forceArrow()
    }

    static func applyToAllWindows() {
        NSApp.windows.forEach(apply)
    }

    static func forceArrow() {
        NSCursor.arrow.set()
        DispatchQueue.main.async {
            NSCursor.arrow.set()
        }
    }

    private static func discardCursorRects(in view: NSView?) {
        guard let view else { return }
        view.discardCursorRects()
        view.subviews.forEach(discardCursorRects)
    }
}

class WindowManager: NSObject, WindowManagerProtocol {
    var window: NSWindow?
    private var globalKeyboardMonitor: Any?
    private var localKeyboardMonitor: Any?

    private let notificationService: NotificationServiceProtocol

    init(notificationService: NotificationServiceProtocol) {
        self.notificationService = notificationService
        super.init()
    }

    // Convenience initializer for backward compatibility during transition to DI
    convenience override init() {
        let notificationService = DIContainer.shared.resolve(NotificationServiceProtocol.self) ?? DefaultNotificationService()
        self.init(notificationService: notificationService)
    }

    @objc func toggleWindowVisibility() {
        guard let window = self.window else { 
            print("ERROR: Cannot toggle window visibility - window is nil")
            return 
        }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
    
    /// Explicitly hide the window without destroying content
    func hideWindow() {
        guard let window = self.window else { return }
        window.orderOut(nil)
    }
    
    func createTransparentWindow() -> NSWindow {
        let windowWidth: CGFloat = 560
        let windowHeight: CGFloat = 500
        
        // Get screen dimensions for centering
        let screenSize = NSScreen.main?.frame.size ?? .zero
        
        // Calculate position (centered on screen)
        let xPos = (screenSize.width - windowWidth) / 2
        let yPos = (screenSize.height - windowHeight) / 2
        
        // Create a non-activating panel so toggling the assistant does not add normal app presence.
        let window = HiddenPanel(
            contentRect: NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.delegate = self
        
        // Set window properties
        window.title = "MoodleLens"
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        window.minSize = NSSize(width: 520, height: 460)
        window.maxSize = NSSize(width: 1200, height: 900)
        
        // Enable window restoration (remembers size/position)
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("MoodleLensMainWindow")
        
        // Enforce content size
        window.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        
        window.alphaValue = 1.0
        window.hasShadow = true
        ArrowCursorLock.install()
        ArrowCursorLock.apply(to: window)
        
        // Apply basic security settings - we'll apply the full security later in showWindow
        applyBasicSecurity(to: window)
        
        // Window should be interactive by default
        window.ignoresMouseEvents = false
        
        return window
    }
    
    @discardableResult
    func showWindow<Content: View>(with rootView: Content) -> NSWindow {
        // Create the window if it doesn't exist
        if window == nil {
            window = createTransparentWindow()
        }
        
        // Set the content view using SwiftUI's hosting controller
        let hostingController = NSHostingController(rootView: rootView)
        
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hostingController.view.autoresizingMask = [.width, .height]
        
        // Allow the content view to receive mouse events
        // hostingController.view.allowedTouchTypes = [] // This line was preventing mouse interaction
        
        window?.contentViewController = hostingController
        
        if let window = window {
            if window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
                window.setContentSize(window.minSize)
            }
            ArrowCursorLock.apply(to: window)
        }
        
        // Secure the window from screen capture using the improved WindowSecurityManager
        window?.secure()
        
        // Show without activating the app so the foreground app keeps focus.
        window?.orderFrontRegardless()
        
        // Ensure window is on all spaces
        window?.collectionBehavior.insert(.canJoinAllSpaces)
        
        // We no longer need to apply accessibility security as it can interfere with mouse interaction
        // WindowSecurityManager.applySecurityTechnique(.accessibilityHidden, to: window!)
        
        // Setup keyboard monitoring
        setupKeyboardMonitoring()
        
        return window!
    }
    
    func setupKeyboardMonitoring() {
        // Remove existing monitors if any
        if let existingMonitor = globalKeyboardMonitor {
            NSEvent.removeMonitor(existingMonitor)
        }
        
        if let existingMonitor = localKeyboardMonitor {
            NSEvent.removeMonitor(existingMonitor)
        }
        
        // Create a local monitor that handles window-specific keyboard shortcuts
        // and passes application shortcuts to AppDelegate
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Get the first responder
            let firstResponder = self.window?.firstResponder
            let isEditingTextField = firstResponder is NSTextField || firstResponder is NSTextView
            
            if AppHotkey.matching(event) != nil {
                return event
            }

            if event.modifierFlags.contains(.function) && event.modifierFlags.contains(.command) {
                if [123, 124, 125, 126].contains(event.keyCode) || isEditingTextField {
                    return event
                }

                return nil
            }
            
            // If typing in a text field, let all regular typing go through
            if isEditingTextField {
                return event
            }
            
            // For all other keys, pass the event through
            return event
        }
        
        print("WindowManager: Keyboard monitoring setup completed")
    }
    
    // Focus detection is no longer needed since we only use Command key combinations
    
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        // This method is kept for future keyboard shortcuts that might be added
        // Window movement is handled by macOS default functionality
        
        if let hotkey = AppHotkey.matching(event) {
            print("WindowManager detected \(hotkey.displayName), allowing AppDelegate to handle it")
            return false
        }
        
        // No special handling needed for other keys
        return false
    }
    

    // Apply basic security settings to a window
    private func applyBasicSecurity(to window: NSWindow) {
        // Apply essential security techniques individually

        // Set specific collection behaviors
        WindowSecurityManager.applySecurityTechnique(.specialCollectionBehavior, to: window)
        
        // Exclude from window menu
        WindowSecurityManager.applySecurityTechnique(.windowMenuExclusion, to: window)
        
        // Set sharing type to none
        WindowSecurityManager.applySecurityTechnique(.sharingTypeNone, to: window)
    }
    
    deinit {
        // Clean up monitors when the manager is deallocated
        if let monitor = globalKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let monitor = localKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Remove notification observers
        notificationService.removeObserver(self)
    }
}

extension WindowManager: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
