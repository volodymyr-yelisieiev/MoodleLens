//
//  SettingsManagerProtocol.swift
//  MoodleLens
//
//  Created on 4/11/25.
//

import Foundation

/// Protocol for app settings management
protocol SettingsManagerProtocol: SelfResolvable {
    /// The OpenAI API key
    var apiKey: String { get set }

    /// AI backend used for responses
    var aiProvider: AIProvider { get set }

    var openAIModel: String { get set }
    var openAIReasoningEffort: String { get set }
    var openAISpeed: String { get set }
    var codexModel: String { get set }
    var codexReasoningEffort: String { get set }
    var codexSpeed: String { get set }

    /// App appearance preference
    var appearanceMode: AppearanceMode { get set }

    /// Current global shortcut bindings
    var allHotkeyBindings: [AppHotkey: HotkeyBinding] { get }

    /// Ask response corner
    var askCorner: AskCorner { get set }

    /// Ask response bubble opacity
    var askOpacity: Double { get set }

    /// Shared instructions for all Ask prompts
    var position: String { get set }

    /// Backward-compatible alias for shared instructions
    var screenshotContext: String { get set }

    /// Backward-compatible alias for shared instructions
    var textContext: String { get set }

    /// Resets all settings to default values
    func resetAll()

    /// Reads one hotkey binding, falling back to the default
    func hotkeyBinding(for hotkey: AppHotkey) -> HotkeyBinding

    /// Persists one hotkey binding
    func setHotkeyBinding(_ binding: HotkeyBinding, for hotkey: AppHotkey)

    /// Resets all hotkeys to defaults
    func resetHotkeyBindings()
}
