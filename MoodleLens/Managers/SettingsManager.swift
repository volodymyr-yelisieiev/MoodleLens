//
//  SettingsManager.swift
//  MoodleLens
//
//  Created by Claude on 4/9/25.
//

import Foundation
import Security

enum AIProvider: String, CaseIterable {
    case openAIAPI = "openai_api"
    case codexCLI = "codex_cli"

    var displayName: String {
        switch self {
        case .openAIAPI:
            return "OpenAI API key"
        case .codexCLI:
            return "Codex OAuth / Codex CLI session"
        }
    }
}

enum AIModelDefaults {
    static let openAIModel = "gpt-5.5"
    static let openAIReasoningEffort = "medium"
    static let openAISpeed = "default"
    static let codexModel = "gpt-5.5"
    static let codexReasoningEffort = "medium"
    static let codexSpeed = "standard"
    static let openAIReasoningEffortValues = ["minimal", "low", "medium", "high", "xhigh"]
    static let codexReasoningEffortValues = ["minimal", "low", "medium", "high", "xhigh"]
    static let openAISpeedValues = ["default", "auto", "flex", "priority", "scale"]
    static let openAIModelValues = [openAIModel]
    static let codexModelValues = [codexModel]
    static let codexSpeedValues = ["standard", "fast"]
}

enum AskCorner: String, CaseIterable, Identifiable {
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft:
            return "Top Left"
        case .topRight:
            return "Top Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomRight:
            return "Bottom Right"
        }
    }
}

struct KeychainCredentialStore {
    let service: String
    let account: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func read() -> (value: String?, status: OSStatus) {
        var readQuery = query
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        readQuery[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return (nil, status)
        }

        return (value.isEmpty ? nil : value, status)
    }

    func save(_ value: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }

        let readStatus = read().status
        if readStatus == errSecSuccess {
            let deleteStatus = delete()
            guard deleteStatus == errSecSuccess else { return deleteStatus }
        } else if readStatus != errSecItemNotFound {
            _ = delete()
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecDuplicateItem else {
            return addStatus
        }

        let deleteStatus = delete()
        guard deleteStatus == errSecSuccess else { return deleteStatus }
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    func delete() -> OSStatus {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}

class SettingsManager: SettingsManagerProtocol {
    // Singleton instance
    static let shared = SettingsManager()
    static let defaultInstructions = """
    Answer Moodle assessment tasks only from the screenshot and parsed Moodle evidence.

    Use browser context as ground truth for question text, hidden dropdowns, selected values, links, and form controls.
    Start with the direct answer or action in one line, then add minimal context only.
    If Moodle is not detected, no task is found, or evidence is missing, say that clearly and list the exact missing checks.
    Never invent dropdown items, menu entries, answers, or other UI states. If they are not visible in screenshot or browser context, say they are not visible.
    """

    // Settings keys
    private struct Keys {
        static let apiKey = "openai_api_key"
        static let position = "user_position"
        static let screenshotContext = "screenshot_context"
        static let textContext = "text_context"
        static let aiProvider = "ai_provider"
        static let openAIModel = "openai_model"
        static let openAIReasoningEffort = "openai_reasoning_effort"
        static let openAISpeed = "openai_speed"
        static let codexModel = "codex_model"
        static let codexReasoningEffort = "codex_reasoning_effort"
        static let codexSpeed = "codex_speed"
        static let appearanceMode = "appearance_mode"
        static let hotkeyBindings = "hotkey_bindings"
        static let askCorner = "ask_corner"
        static let askOpacity = "ask_opacity"
    }

    // Notification service for dependency injection
    private let notificationService: NotificationServiceProtocol
    private let userDefaults: UserDefaults
    private let keychainStore: KeychainCredentialStore

    // Default initializer with dependencies
    init(
        notificationService: NotificationServiceProtocol,
        userDefaults: UserDefaults = .standard,
        keychainStore: KeychainCredentialStore = KeychainCredentialStore(
            service: "io.github.volodymyryelisieiev.moodlelens",
            account: Keys.apiKey
        )
    ) {
        self.notificationService = notificationService
        self.userDefaults = userDefaults
        self.keychainStore = keychainStore
    }

    // Convenience initializer for singleton during transition to DI
    private convenience init() {
        // During transition, fallback to a default notification service
        let notificationService = DIContainer.shared.resolve(NotificationServiceProtocol.self) ?? DefaultNotificationService()
        self.init(notificationService: notificationService)
    }

    // MARK: - API Key

    var apiKey: String {
        get {
            let keychainResult = keychainStore.read()
            if let keychainValue = keychainResult.value {
                userDefaults.removeObject(forKey: Keys.apiKey)
                return keychainValue
            }

            if keychainResult.status != errSecSuccess && keychainResult.status != errSecItemNotFound {
                postKeychainError("Could not read the OpenAI API key from macOS Keychain (OSStatus \(keychainResult.status)). Open Settings and paste the key again.")
            }

            return ""
        }
        set {
            updateAPIKey(newValue)
        }
    }

    @discardableResult
    func updateAPIKey(_ newValue: String) -> Bool {
        let status: OSStatus
        if newValue.isEmpty {
            status = keychainStore.delete()
        } else {
            status = keychainStore.save(newValue)
        }

        userDefaults.removeObject(forKey: Keys.apiKey)
        guard status == errSecSuccess else {
            let action = newValue.isEmpty ? "remove" : "save"
            postKeychainError("Could not \(action) the OpenAI API key in macOS Keychain (OSStatus \(status)). Check Keychain access and try again.")
            return false
        }

        return true
    }

    var aiProvider: AIProvider {
        get {
            let rawValue = userDefaults.string(forKey: Keys.aiProvider)
            return rawValue.flatMap(AIProvider.init(rawValue:)) ?? .openAIAPI
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.aiProvider)
        }
    }

    var openAIModel: String {
        get { userDefaults.string(forKey: Keys.openAIModel) ?? AIModelDefaults.openAIModel }
        set { userDefaults.set(cleanModel(newValue, fallback: AIModelDefaults.openAIModel), forKey: Keys.openAIModel) }
    }

    var openAIReasoningEffort: String {
        get { cleanReasoning(userDefaults.string(forKey: Keys.openAIReasoningEffort), fallback: AIModelDefaults.openAIReasoningEffort) }
        set { userDefaults.set(cleanReasoning(newValue, fallback: AIModelDefaults.openAIReasoningEffort), forKey: Keys.openAIReasoningEffort) }
    }

    var openAISpeed: String {
        get { cleanSpeed(userDefaults.string(forKey: Keys.openAISpeed), fallback: AIModelDefaults.openAISpeed) }
        set { userDefaults.set(cleanSpeed(newValue, fallback: AIModelDefaults.openAISpeed), forKey: Keys.openAISpeed) }
    }

    var codexModel: String {
        get { userDefaults.string(forKey: Keys.codexModel) ?? AIModelDefaults.codexModel }
        set { userDefaults.set(cleanModel(newValue, fallback: AIModelDefaults.codexModel), forKey: Keys.codexModel) }
    }

    var codexReasoningEffort: String {
        get { cleanReasoning(userDefaults.string(forKey: Keys.codexReasoningEffort), fallback: AIModelDefaults.codexReasoningEffort) }
        set { userDefaults.set(cleanReasoning(newValue, fallback: AIModelDefaults.codexReasoningEffort), forKey: Keys.codexReasoningEffort) }
    }

    var codexSpeed: String {
        get { cleanCodexSpeed(userDefaults.string(forKey: Keys.codexSpeed)) }
        set { userDefaults.set(cleanCodexSpeed(newValue), forKey: Keys.codexSpeed) }
    }

    var appearanceMode: AppearanceMode {
        get {
            let rawValue = userDefaults.string(forKey: Keys.appearanceMode)
            return rawValue.flatMap(AppearanceMode.init(rawValue:)) ?? .system
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.appearanceMode)
        }
    }

    var allHotkeyBindings: [AppHotkey: HotkeyBinding] {
        var bindings = storedHotkeyBindings
        for hotkey in AppHotkey.registeredHotkeys where bindings[hotkey.rawValue] == nil {
            bindings[hotkey.rawValue] = hotkey.defaultBinding
        }
        return Dictionary(uniqueKeysWithValues: bindings.compactMap { rawValue, binding in
            guard let hotkey = AppHotkey(rawValue: rawValue) else { return nil }
            return (hotkey, binding)
        })
    }

    func hotkeyBinding(for hotkey: AppHotkey) -> HotkeyBinding {
        storedHotkeyBindings[hotkey.rawValue] ?? hotkey.defaultBinding
    }

    func setHotkeyBinding(_ binding: HotkeyBinding, for hotkey: AppHotkey) {
        var bindings = storedHotkeyBindings
        bindings[hotkey.rawValue] = binding
        saveHotkeyBindings(bindings)
    }

    func resetHotkeyBindings() {
        userDefaults.removeObject(forKey: Keys.hotkeyBindings)
    }

    var askCorner: AskCorner {
        get {
            let rawValue = userDefaults.string(forKey: Keys.askCorner)
            return rawValue.flatMap(AskCorner.init(rawValue:)) ?? .bottomRight
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.askCorner)
        }
    }

    var askOpacity: Double {
        get {
            let value = userDefaults.object(forKey: Keys.askOpacity) as? Double ?? 0.75
            return min(1.0, max(0.35, value))
        }
        set {
            userDefaults.set(min(1.0, max(0.35, newValue)), forKey: Keys.askOpacity)
        }
    }

    private var storedHotkeyBindings: [UInt32: HotkeyBinding] {
        guard let data = userDefaults.data(forKey: Keys.hotkeyBindings),
              let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let rawValue = UInt32(key) else { return nil }
            return (rawValue, value)
        })
    }

    private func saveHotkeyBindings(_ bindings: [UInt32: HotkeyBinding]) {
        let encoded = Dictionary(uniqueKeysWithValues: bindings.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            userDefaults.set(data, forKey: Keys.hotkeyBindings)
        }
    }

    // MARK: - Context Settings

    var position: String {
        get {
            userDefaults.string(forKey: Keys.position)
                ?? userDefaults.string(forKey: Keys.screenshotContext)
                ?? userDefaults.string(forKey: Keys.textContext)
                ?? Self.defaultInstructions
        }
        set {
            let limitedValue = String(newValue.prefix(2000))
            userDefaults.set(limitedValue, forKey: Keys.position)
            userDefaults.removeObject(forKey: Keys.screenshotContext)
            userDefaults.removeObject(forKey: Keys.textContext)
        }
    }

    var screenshotContext: String {
        get {
            position
        }
        set {
            position = newValue
        }
    }

    var textContext: String {
        get {
            position
        }
        set {
            position = newValue
        }
    }

    // MARK: - Reset Settings

    func resetAll() {
        let deleteStatus = keychainStore.delete()
        if deleteStatus != errSecSuccess {
            postKeychainError("Could not remove the OpenAI API key from macOS Keychain (OSStatus \(deleteStatus)). Check Keychain access and try again.")
        }
        userDefaults.removeObject(forKey: Keys.apiKey)
        userDefaults.removeObject(forKey: Keys.position)
        userDefaults.removeObject(forKey: Keys.screenshotContext)
        userDefaults.removeObject(forKey: Keys.textContext)
        userDefaults.removeObject(forKey: Keys.aiProvider)
        userDefaults.removeObject(forKey: Keys.openAIModel)
        userDefaults.removeObject(forKey: Keys.openAIReasoningEffort)
        userDefaults.removeObject(forKey: Keys.openAISpeed)
        userDefaults.removeObject(forKey: Keys.codexModel)
        userDefaults.removeObject(forKey: Keys.codexReasoningEffort)
        userDefaults.removeObject(forKey: Keys.codexSpeed)
        userDefaults.removeObject(forKey: Keys.appearanceMode)
        userDefaults.removeObject(forKey: Keys.hotkeyBindings)
        userDefaults.removeObject(forKey: Keys.askCorner)
        userDefaults.removeObject(forKey: Keys.askOpacity)
    }

    private func postKeychainError(_ message: String) {
        notificationService.post(
            name: .openaiError,
            object: ["error": message]
        )
    }

    private func cleanModel(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(80))
    }

    private func cleanReasoning(_ value: String?, fallback: String) -> String {
        cleanProviderOption(value, fallback: fallback)
    }

    private func cleanSpeed(_ value: String?, fallback: String) -> String {
        cleanProviderOption(value, fallback: fallback)
    }

    private func cleanCodexSpeed(_ value: String?) -> String {
        cleanProviderOption(value, fallback: AIModelDefaults.codexSpeed)
    }

    private func cleanProviderOption(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(80))
    }
}
