//
//  GlobalHotkeyManager.swift
//  MoodleLens
//
//  Created on 4/10/25.
//

import Cocoa
import Carbon

struct HotkeyBinding: Codable, Equatable {
    static let command = UInt32(1 << 8)
    static let shift = UInt32(1 << 9)
    static let option = UInt32(1 << 11)
    static let control = UInt32(1 << 12)
    static let function = UInt32(1 << 17)

    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let modifiers = Self.modifiers(from: event.modifierFlags)
        guard modifiers & (Self.command | Self.option | Self.control) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var displayName: String {
        var parts: [String] = []
        if modifiers & Self.function != 0 { parts.append("Fn") }
        if modifiers & Self.control != 0 { parts.append("Ctrl") }
        if modifiers & Self.option != 0 { parts.append("Opt") }
        if modifiers & Self.shift != 0 { parts.append("Shift") }
        if modifiers & Self.command != 0 { parts.append("Cmd") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    var shortcutLabel: String {
        displayName
            .replacingOccurrences(of: "Fn", with: "FN")
            .replacingOccurrences(of: "Cmd", with: "⌘")
            .replacingOccurrences(of: "Opt", with: "⌥")
            .replacingOccurrences(of: "Ctrl", with: "⌃")
            .replacingOccurrences(of: "Shift", with: "⇧")
    }

    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode && Self.modifiers(from: event.modifierFlags) == modifiers
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers |= command }
        if flags.contains(.shift) { modifiers |= shift }
        if flags.contains(.option) { modifiers |= option }
        if flags.contains(.control) { modifiers |= control }
        if flags.contains(.function) { modifiers |= function }
        return modifiers
    }

    private static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 49: "Space", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

enum AppHotkey: UInt32, CaseIterable {
    case openSettings = 1
    case ask = 2
    case toggleBubble = 3
    case clearChat = 4

    var displayName: String {
        binding.displayName
    }

    var shortcutLabel: String {
        binding.shortcutLabel
    }

    var binding: HotkeyBinding {
        SettingsManager.shared.hotkeyBinding(for: self)
    }

    var defaultBinding: HotkeyBinding {
        let modifiers = HotkeyBinding.option
        switch self {
        case .openSettings:
            return HotkeyBinding(keyCode: 5, modifiers: modifiers)
        case .ask:
            return HotkeyBinding(keyCode: 0, modifiers: modifiers)
        case .toggleBubble:
            return HotkeyBinding(keyCode: 11, modifiers: modifiers)
        case .clearChat:
            return HotkeyBinding(keyCode: 8, modifiers: modifiers)
        }
    }

    var uiLabel: String {
        switch self {
        case .openSettings:
            return "SETTINGS"
        case .ask:
            return "ASK"
        case .toggleBubble:
            return "BUBBLE"
        case .clearChat:
            return "CLEAR"
        }
    }

    static var registeredHotkeys: [AppHotkey] {
        [.openSettings, .ask, .toggleBubble, .clearChat]
    }

    static func matching(_ event: NSEvent) -> AppHotkey? {
        registeredHotkeys.first { $0.binding.matches(event) }
    }
}

/// A manager class that registers and handles global hotkeys that work system-wide,
/// even when the application doesn't have focus.
class GlobalHotkeyManager {
    // Singleton instance
    static let shared = GlobalHotkeyManager()
    
    private var hotKeyRefs: [AppHotkey: EventHotKeyRef] = [:]
    private var eventHandlerInstalled = false
    
    // Private initializer for singleton
    private init() {}
    
    // Register global hotkeys
    func registerHotkeys() {
        unregisterHotkeys()
        for hotkey in AppHotkey.registeredHotkeys {
            tryRegisterHotkey(hotkey)
        }
        
        // Install event handler even if registration fails
        installEventHandler()
    }
    
    // Unregister all global hotkeys
    func unregisterHotkeys() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    func reloadHotkeys() {
        unregisterHotkeys()
        registerHotkeys()
    }
    
    // Try to register a hotkey with given parameters
    private func tryRegisterHotkey(_ hotkey: AppHotkey) {
        // Create the hotkey ID
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(bitPattern: 0x4852444D) // 'HRDM' signature
        hotKeyID.id = hotkey.rawValue

        var ref: EventHotKeyRef?
        
        // Register the hotkey
        let result = RegisterEventHotKey(
            hotkey.binding.keyCode,
            hotkey.binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        
        if result == noErr {
            hotKeyRefs[hotkey] = ref
            return
        }

        let reason = result == -9878 ? "already registered by another app" : "registration failed with OSStatus \(result)"
        let message = "Hotkey \(hotkey.displayName) \(reason). Change the conflicting shortcut or quit the other app."
        print(message)
        NotificationCenter.default.post(name: .hotkeyRegistrationFailed, object: ["error": message])
    }
    
    // Install event handler for processing hotkey events
    private func installEventHandler() {
        guard !eventHandlerInstalled else { return }

        // Define the event types we want to handle
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Install the callback handler
        let callback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            
            // Extract the hotkey ID
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if err != noErr {
                return err
            }
            
            guard let hotkey = AppHotkey(rawValue: hotKeyID.id) else {
                return OSStatus(eventNotHandledErr)
            }

            DispatchQueue.main.async {
                GlobalHotkeyManager.shared.perform(hotkey)
            }

            return noErr
        }
        
        // Create and install the event handler
        var handlerRef: EventHandlerRef?
        let err = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        
        if err != noErr {
            print("Failed to install event handler. Error: \(err)")
        } else {
            eventHandlerInstalled = true
        }
    }

    private func perform(_ hotkey: AppHotkey) {
        switch hotkey {
        case .openSettings:
            if let appDelegate = DIContainer.shared.resolve(AppDelegateProtocol.self) {
                appDelegate.showSettings()
            } else if let appDelegate = NSApp.delegate as? AppDelegateProtocol {
                appDelegate.showSettings()
            }

        case .ask:
            AskController.shared.ask()

        case .toggleBubble:
            AskController.shared.toggleBubble()

        case .clearChat:
            AskController.shared.clearHistory()
        }
    }
}
