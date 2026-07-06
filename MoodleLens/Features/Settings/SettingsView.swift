//
//  SettingsView.swift
//  MoodleLens
//

import SwiftUI
import AppKit
import CoreGraphics

struct SettingsView: View {
    let isFirstRunSetup: Bool
    let onConfigured: () -> Void
    private let permissionManager: PermissionManagerProtocol

    @AppStorage("appearance_mode") private var appearanceModeRaw = AppearanceMode.system.rawValue
    @State private var aiProvider: AIProvider
    @State private var apiKey: String
    @State private var openAIModel: String
    @State private var openAIReasoningEffort: String
    @State private var openAISpeed: String
    @State private var openAIModelValues: [String]
    @State private var isRefreshingOpenAIModels = false
    @State private var openAIModelStatus: String?
    @State private var codexModel: String
    @State private var codexReasoningEffort: String
    @State private var codexSpeed: String
    @State private var codexModelValues: [String]
    @State private var isRefreshingCodexModels = false
    @State private var codexModelStatus: String?
    @State private var position: String
    @State private var showSavedMessage = false
    @State private var showAdvancedSettings = false
    @State private var validationMessage: String?
    @State private var codexStatus: CodexCLIStatus
    @State private var isRefreshingCodexStatus = false
    @State private var screenRecordingAllowed: Bool
    @State private var accessibilityAllowed: Bool
    @State private var browserContextAllowed: Bool
    @State private var permissionMessage: String?
    @State private var showUninstallConfirmation = false
    @State private var hotkeyBindings: [AppHotkey: HotkeyBinding]
    @State private var recordingHotkey: AppHotkey?
    @State private var hotkeyRecorderMonitor: Any?
    @State private var hotkeyMessage: String?
    @State private var askCorner: AskCorner
    @State private var askOpacity: Double
    @State private var askHistory: [Message]
    @State private var browserContextStatus: String

    init(isFirstRunSetup: Bool = false, onConfigured: @escaping () -> Void = {}) {
        self.isFirstRunSetup = isFirstRunSetup
        self.onConfigured = onConfigured
        self.permissionManager = DIContainer.shared.resolve(PermissionManagerProtocol.self) ?? PermissionManager.shared
        _aiProvider = State(initialValue: SettingsManager.shared.aiProvider)
        _apiKey = State(initialValue: SettingsManager.shared.apiKey)
        _openAIModel = State(initialValue: SettingsManager.shared.openAIModel)
        _openAIReasoningEffort = State(initialValue: SettingsManager.shared.openAIReasoningEffort)
        _openAISpeed = State(initialValue: SettingsManager.shared.openAISpeed)
        _openAIModelValues = State(initialValue: OpenAIModelCatalog.fallbackModelIDs(selected: SettingsManager.shared.openAIModel))
        _codexModel = State(initialValue: SettingsManager.shared.codexModel)
        _codexReasoningEffort = State(initialValue: SettingsManager.shared.codexReasoningEffort)
        _codexSpeed = State(initialValue: SettingsManager.shared.codexSpeed)
        _codexModelValues = State(initialValue: CodexModelCatalog.fallbackModelIDs(selected: SettingsManager.shared.codexModel))
        _position = State(initialValue: SettingsManager.shared.position)
        _codexStatus = State(initialValue: CodexCLIStatus(
            executablePath: nil,
            isLoggedIn: nil,
            message: "Checking Codex CLI status..."
        ))
        _screenRecordingAllowed = State(initialValue: false)
        _accessibilityAllowed = State(initialValue: AccessibilityPermissions.checkAccessibilityPermissions())
        _browserContextAllowed = State(initialValue: BrowserContextProvider.frontmostBrowserHasAutomationPermission())
        _hotkeyBindings = State(initialValue: SettingsManager.shared.allHotkeyBindings)
        _askCorner = State(initialValue: SettingsManager.shared.askCorner)
        _askOpacity = State(initialValue: SettingsManager.shared.askOpacity)
        _askHistory = State(initialValue: AskController.shared.sessionHistorySnapshot())
        _browserContextStatus = State(initialValue: BrowserContextProvider.lastStatusSummary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isFirstRunSetup ? "Set Up MoodleLens" : "Settings")
                        .font(.title2)
                        .bold()

                    if isFirstRunSetup {
                        Text("Choose a provider and confirm permissions before analyzing Moodle tasks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("AI Provider") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Provider", selection: $aiProvider) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        providerDetails

                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                }

                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Theme", selection: $appearanceModeRaw) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("System follows macOS. Light and Dark pin MoodleLens until changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }

                GroupBox("Hotkeys") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(AppHotkey.registeredHotkeys, id: \.self) { hotkey in
                            hotkeyRow(hotkey)
                        }

                        HStack(spacing: 10) {
                            Button("Reset Defaults", action: resetHotkeys)
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                            if let hotkeyMessage {
                                Label(hotkeyMessage, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                }

                GroupBox("Ask") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Corner", selection: $askCorner) {
                            ForEach(AskCorner.allCases) { corner in
                                Text(corner.displayName).tag(corner)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Bubble Opacity")
                                Spacer()
                                Text("\(Int(askOpacity * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $askOpacity, in: 0.35...1.0)
                        }

                        HStack {
                            Text("Bubble auto-hides after 10 seconds. Ask history stays in memory for this app session.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Clear Ask History") {
                                clearAskHistory()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        askHistorySection
                    }
                    .padding(12)
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(
                            title: "Screen Recording",
                            isAllowed: screenRecordingAllowed,
                            detail: screenRecordingAllowed
                                ? "Ready for Moodle page screenshots. Restart MoodleLens if you granted it moments ago."
                                : "Required for Moodle page screenshots. Local ad-hoc builds may need a fresh grant after reinstall.",
                            actionTitle: screenRecordingAllowed ? "Open Settings" : "Grant / Repair",
                            action: screenRecordingAllowed ? openScreenRecordingSettings : grantScreenRecording
                        )

                        Divider()

                        permissionRow(
                            title: "Accessibility",
                            isAllowed: accessibilityAllowed,
                            detail: accessibilityAllowed
                                ? "Ready for global hotkeys."
                                : "Required for global hotkeys.",
                            actionTitle: accessibilityAllowed ? "Open Settings" : "Grant / Repair",
                            action: accessibilityAllowed ? openAccessibilitySettings : grantAccessibility
                        )

                        Divider()

                        permissionRow(
                            title: "Browser Context",
                            isAllowed: browserContextAllowed,
                            detail: browserContextDetail,
                            actionTitle: browserContextAllowed ? "Open Settings" : "Grant / Repair",
                            action: browserContextAllowed ? BrowserContextProvider.openAutomationSettings : grantBrowserContext
                        )

                        HStack(spacing: 10) {
                            Button("Refresh Permission Status", action: refreshPermissions)
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                            if let permissionMessage {
                                Label(permissionMessage, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(12)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation {
                                showAdvancedSettings.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Advanced")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: showAdvancedSettings ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showAdvancedSettings {
                            contextEditor

                            Button("Reset to Default", action: resetSelectedContext)
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                }

                GroupBox("Danger Zone") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Uninstall MoodleLens")
                            Text("Remove the app, local settings, API key, caches, logs, and temporary files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Uninstall MoodleLens...", role: .destructive) {
                            showUninstallConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                }

                HStack(spacing: 12) {
                    Button(isFirstRunSetup ? "Save and Continue" : "Save Settings", action: saveSettings)
                        .buttonStyle(.borderedProminent)

                    if isFirstRunSetup {
                        Button("Later") {
                            NSApp.keyWindow?.performClose(nil)
                        }
                        .buttonStyle(.bordered)
                    }

                    if showSavedMessage {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 8)

                GroupBox {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("MoodleLens")
                                .font(.headline)
                            Text(appVersionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Check for Updates") {
                            DIContainer.shared.resolve(AppDelegateProtocol.self)?.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 540, height: isFirstRunSetup ? 620 : 580)
        .preferredColorScheme(currentAppearanceMode.colorScheme)
        .onAppear {
            ArrowCursorLock.applyToAllWindows()
            refreshPermissions()
            refreshCodexStatus()
            refreshOpenAIModels()
            refreshCodexModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: PermissionManager.permissionStatusChanged)) { _ in
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: AskController.historyDidChange)) { _ in
            refreshAskHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenshotError)) { _ in
            refreshPermissions()
        }
        .onDisappear {
            stopHotkeyRecording()
        }
        .alert("Uninstall MoodleLens?", isPresented: $showUninstallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive, action: uninstallMoodleLens)
        } message: {
            Text("This removes MoodleLens from Applications and deletes local settings, Keychain API key, caches, logs, and temporary files.")
        }
        .onChange(of: aiProvider) { _, provider in
            validationMessage = nil
            if provider == .codexCLI {
                refreshCodexStatus()
                refreshCodexModels()
            } else {
                refreshOpenAIModels()
            }
        }
        .onChange(of: openAIModel) { _, value in
            openAIModelValues = OpenAIModelCatalog.mergedModelIDs(openAIModelValues, selected: value)
            SettingsManager.shared.openAIModel = value
        }
        .onChange(of: openAIReasoningEffort) { _, value in
            SettingsManager.shared.openAIReasoningEffort = value
        }
        .onChange(of: openAISpeed) { _, value in
            SettingsManager.shared.openAISpeed = value
        }
        .onChange(of: codexModel) { _, value in
            codexModelValues = CodexModelCatalog.mergedModelIDs(codexModelValues, selected: value)
            SettingsManager.shared.codexModel = value
        }
        .onChange(of: codexReasoningEffort) { _, value in
            SettingsManager.shared.codexReasoningEffort = value
        }
        .onChange(of: codexSpeed) { _, value in
            SettingsManager.shared.codexSpeed = value
        }
        .onChange(of: appearanceModeRaw) { _, rawValue in
            SettingsManager.shared.appearanceMode = AppearanceMode(rawValue: rawValue) ?? .system
        }
        .onChange(of: askCorner) { _, value in
            SettingsManager.shared.askCorner = value
        }
        .onChange(of: askOpacity) { _, value in
            SettingsManager.shared.askOpacity = value
        }
    }

    private func availableModels(for provider: AIProvider) -> [String] {
        switch provider {
        case .openAIAPI:
            return openAIModelValues
        case .codexCLI:
            return codexModelValues
        }
    }

    private func availableReasoningValues(for provider: AIProvider, model: String) -> [String] {
        if provider == .openAIAPI {
            return AIModelCapability.supportsReasoning(model: model)
                ? AIModelDefaults.openAIReasoningEffortValues
                : [AIModelDefaults.openAIReasoningEffort]
        }

        return AIModelDefaults.codexReasoningEffortValues
    }

    private func mergedOptions(_ values: [String], selected: String) -> [String] {
        var seen = Set<String>()
        var list = values.filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
        let selected = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty && !seen.contains(selected) {
            list.insert(selected, at: 0)
        }
        return list
    }

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "Version \(version) (\(build))"
    }

    @ViewBuilder
    private var providerDetails: some View {
        switch aiProvider {
        case .openAIAPI:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Paste your OpenAI API key here", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Paste API key from clipboard")
                }

                Text("MoodleLens stores this key in macOS Keychain and does not log it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(isRefreshingOpenAIModels ? "Refreshing Models..." : "Refresh Models", action: refreshOpenAIModels)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRefreshingOpenAIModels || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let openAIModelStatus {
                        Text(openAIModelStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                modelControls(
                    model: $openAIModel,
                    modelValues: availableModels(for: aiProvider),
                    reasoning: AIModelCapability.supportsReasoning(model: openAIModel) ? $openAIReasoningEffort : nil,
                    reasoningValues: availableReasoningValues(for: .openAIAPI, model: openAIModel),
                    tier: $openAISpeed,
                    tierValues: AIModelDefaults.openAISpeedValues
                )
            }

        case .codexCLI:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(isRefreshingCodexModels ? "Refreshing Models..." : "Refresh Models", action: refreshCodexModels)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRefreshingCodexModels || !codexStatus.isInstalled)

                    if let codexModelStatus {
                        Text(codexModelStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                modelControls(
                    model: $codexModel,
                    modelValues: availableModels(for: aiProvider),
                    reasoning: $codexReasoningEffort,
                    reasoningValues: AIModelDefaults.codexReasoningEffortValues
                )

                statusLine(
                    codexStatus.isInstalled ? "Codex CLI installed" : "Codex CLI not found",
                    isOK: codexStatus.isInstalled
                )

                if let executablePath = codexStatus.executablePath {
                    Text(executablePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                statusLine(
                    codexStatus.isLoggedIn == true ? "Logged in with official Codex CLI" : "Login required",
                    isOK: codexStatus.isLoggedIn == true
                )

                Text("MoodleLens does not handle OAuth tokens. Run `codex login` or `codex login --device-auth` in Terminal, then refresh this status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(codexStatus.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isRefreshingCodexStatus ? "Checking..." : "Refresh Codex Status", action: refreshCodexStatus)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRefreshingCodexStatus)
            }
        }

        Text(activeModelSummary)
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("The selected provider is used for Moodle Ask prompts.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var contextEditor: some View {
        editor(text: $position, count: position.count, help: "Used for every Ask prompt.")
    }

    @ViewBuilder
    private var askHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Session History")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text("\(askHistory.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if askHistory.isEmpty {
                Text("No Ask history in this app session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(askHistory.enumerated()), id: \.element.id) { index, message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(askHistoryTitle(for: message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(MarkdownParser.parse(text: askHistoryText(for: message)))
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if index < askHistory.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 220)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var activeModelSummary: String {
        switch aiProvider {
        case .openAIAPI:
            let reasoning = AIModelCapability.supportsReasoning(model: openAIModel)
                ? " Reasoning: \(openAIReasoningEffort)."
                : ""
            return "Active model: \(openAIModel).\(reasoning) API tier: \(openAISpeed)."
        case .codexCLI:
            return "Active model: \(codexModel). Reasoning: \(codexReasoningEffort)."
        }
    }

    private func modelControls(
        model: Binding<String>,
        modelValues: [String],
        reasoning: Binding<String>? = nil,
        reasoningValues: [String],
        tier: Binding<String>? = nil,
        tierValues: [String] = AIModelDefaults.openAISpeedValues
    ) -> some View {
        let modelItems = mergedOptions(modelValues, selected: model.wrappedValue)
        let reasoningItems = mergedOptions(reasoningValues, selected: reasoning?.wrappedValue ?? "")
        let tierItems = mergedOptions(tierValues, selected: tier?.wrappedValue ?? AIModelDefaults.openAISpeed)

        return VStack(alignment: .leading, spacing: 8) {
            if modelItems.count > 1 {
                Picker("Available Models", selection: model) {
                    ForEach(modelItems, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
            }

            if modelItems.count <= 1 {
                TextField("Model", text: model)
                    .textFieldStyle(.roundedBorder)
            }

            if let reasoning {
                Picker("Reasoning", selection: reasoning) {
                    ForEach(reasoningItems, id: \.self) { value in
                        Text(value == "xhigh" ? "Xhigh" : value.capitalized).tag(value)
                    }
                }
            }

            if let tier {
                Picker("API Tier", selection: tier) {
                    ForEach(tierItems, id: \.self) { value in
                        Text(value.capitalized).tag(value)
                    }
                }
            }
        }
    }

    private func editor(text: Binding<String>, count: Int, help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: text)
                .font(.body)
                .frame(height: 160)

            HStack {
                Text("\(count)/2000 characters")
                Spacer()
                Text(help)
            }
            .font(.caption)
            .foregroundColor(count > 2000 ? .red : .secondary)
        }
    }

    private func permissionRow(
        title: String,
        isAllowed: Bool,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isAllowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isAllowed ? .green : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func hotkeyRow(_ hotkey: AppHotkey) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hotkeyLabel(for: hotkey))
                Text(hotkey.uiLabel.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text((hotkeyBindings[hotkey] ?? hotkey.defaultBinding).shortcutLabel)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Button(recordingHotkey == hotkey ? "Press Keys..." : "Record") {
                startHotkeyRecording(for: hotkey)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func hotkeyLabel(for hotkey: AppHotkey) -> String {
        switch hotkey {
        case .openSettings:
            return "Open Settings"
        case .ask:
            return "Ask"
        case .toggleBubble:
            return "Toggle Bubble"
        case .clearChat:
            return "Clear Chat"
        }
    }

    private func statusLine(_ text: String, isOK: Bool) -> some View {
        Label(text, systemImage: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(isOK ? .green : .orange)
    }

    private func pasteFromClipboard() {
        if let clipboardContent = NSPasteboard.general.string(forType: .string) {
            apiKey = clipboardContent
        }
    }

    private func refreshOpenAIModels() {
        guard aiProvider == .openAIAPI else { return }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            openAIModelValues = OpenAIModelCatalog.fallbackModelIDs(selected: openAIModel)
            openAIModelStatus = "Save an API key to fetch current models."
            return
        }

        isRefreshingOpenAIModels = true
        openAIModelStatus = "Fetching current models..."

        Task {
            do {
                let ids = try await OpenAIModelCatalog.fetchModelIDs(apiKey: trimmedKey)
                await MainActor.run {
                    openAIModelValues = OpenAIModelCatalog.mergedModelIDs(ids, selected: openAIModel)
                    openAIModelStatus = ids.isEmpty ? "No text models returned; custom model kept." : "Fetched \(ids.count) models."
                    isRefreshingOpenAIModels = false
                }
            } catch {
                await MainActor.run {
                    openAIModelValues = OpenAIModelCatalog.fallbackModelIDs(selected: openAIModel)
                    openAIModelStatus = "\(error.localizedDescription) Custom model kept."
                    isRefreshingOpenAIModels = false
                }
            }
        }
    }

    private func refreshCodexModels() {
        guard aiProvider == .codexCLI else { return }

        isRefreshingCodexModels = true
        codexModelStatus = "Fetching Codex models..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ids = try CodexModelCatalog.fetchModelIDs()
                DispatchQueue.main.async {
                    codexModelValues = CodexModelCatalog.mergedModelIDs(ids, selected: codexModel)
                    codexModelStatus = ids.isEmpty ? "No Codex models returned; custom model kept." : "Fetched \(ids.count) models."
                    isRefreshingCodexModels = false
                }
            } catch {
                DispatchQueue.main.async {
                    codexModelValues = CodexModelCatalog.fallbackModelIDs(selected: codexModel)
                    codexModelStatus = "\(error.localizedDescription) Custom model kept."
                    isRefreshingCodexModels = false
                }
            }
        }
    }

    private func startHotkeyRecording(for hotkey: AppHotkey) {
        stopHotkeyRecording()
        recordingHotkey = hotkey
        hotkeyMessage = "Press a shortcut with Command, Control, or Option. Escape cancels."

        hotkeyRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopHotkeyRecording()
                hotkeyMessage = "Recording cancelled."
                return nil
            }

            guard let binding = HotkeyBinding(event: event) else {
                hotkeyMessage = "Shortcut must include Command, Control, or Option."
                return nil
            }

            if let conflict = hotkeyBindings.first(where: { otherHotkey, otherBinding in
                otherHotkey != hotkey && otherBinding == binding
            }) {
                hotkeyMessage = "Conflict with \(hotkeyLabel(for: conflict.key))."
                return nil
            }

            SettingsManager.shared.setHotkeyBinding(binding, for: hotkey)
            hotkeyBindings = SettingsManager.shared.allHotkeyBindings
            GlobalHotkeyManager.shared.reloadHotkeys()
            hotkeyMessage = "\(hotkeyLabel(for: hotkey)) set to \(binding.displayName)."
            stopHotkeyRecording()
            return nil
        }
    }

    private func stopHotkeyRecording() {
        if let monitor = hotkeyRecorderMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyRecorderMonitor = nil
        recordingHotkey = nil
    }

    private func resetHotkeys() {
        stopHotkeyRecording()
        SettingsManager.shared.resetHotkeyBindings()
        hotkeyBindings = SettingsManager.shared.allHotkeyBindings
        GlobalHotkeyManager.shared.reloadHotkeys()
        hotkeyMessage = "Hotkeys reset."
    }

    private func refreshAskHistory() {
        askHistory = AskController.shared.sessionHistorySnapshot()
    }

    private func clearAskHistory() {
        AskController.shared.clearHistory()
        refreshAskHistory()
        hotkeyMessage = "Ask history cleared."
    }

    private func askHistoryTitle(for message: Message) -> String {
        switch message.type {
        case .user:
            return "Task"
        case .assistant:
            return "Answer"
        }
    }

    private func askHistoryText(for message: Message) -> String {
        message.contents.map(\.content).joined(separator: "\n")
    }

    private func resetSelectedContext() {
        position = SettingsManager.defaultInstructions
    }

    private func saveSettings() {
        validationMessage = nil

        if aiProvider == .openAIAPI {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                validationMessage = "Paste a non-empty OpenAI API key, or choose Codex OAuth / Codex CLI session."
                return
            }
            apiKey = trimmedKey
        }

        SettingsManager.shared.aiProvider = aiProvider
        SettingsManager.shared.openAIModel = openAIModel
        SettingsManager.shared.openAIReasoningEffort = openAIReasoningEffort
        SettingsManager.shared.openAISpeed = openAISpeed
        SettingsManager.shared.codexModel = codexModel
        SettingsManager.shared.codexReasoningEffort = codexReasoningEffort
        SettingsManager.shared.codexSpeed = codexSpeed

        if aiProvider == .codexCLI {
            let currentStatus = CodexCLIClient.currentStatus()
            codexStatus = currentStatus
            guard currentStatus.isReady else {
                validationMessage = currentStatus.isInstalled
                    ? "Run codex login or codex login --device-auth before using Codex."
                    : "Install Codex CLI before using the Codex provider."
                return
            }
        }

        if aiProvider == .openAIAPI {
            let apiKeySaved = SettingsManager.shared.updateAPIKey(apiKey)
            guard apiKeySaved else {
                validationMessage = "macOS Keychain rejected the API key. Check Keychain access, then paste it again."
                return
            }
            DIContainer.shared.resolve(OpenAIClientProtocol.self)?.setAPIKey(apiKey)
            refreshOpenAIModels()
        }

        SettingsManager.shared.position = String(position.prefix(2000))

        onConfigured()

        withAnimation {
            showSavedMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedMessage = false
            }
        }
    }

    private func refreshPermissions() {
        permissionManager.screenCapturePermissionStatus { status in
            screenRecordingAllowed = status == .authorized
        }
        accessibilityAllowed = AccessibilityPermissions.checkAccessibilityPermissions()
        browserContextAllowed = BrowserContextProvider.frontmostBrowserHasAutomationPermission()
        browserContextStatus = BrowserContextProvider.lastStatusSummary
    }

    private func grantScreenRecording() {
        permissionMessage = "Repairing Screen Recording permission..."
        permissionManager.resetPermission(.screenCapture) { _ in
            permissionManager.requestScreenCapturePermission { granted in
                refreshPermissions()
                if granted {
                    permissionMessage = "Restart MoodleLens after granting Screen Recording."
                } else {
                    permissionMessage = "Enable MoodleLens in Screen Recording, then restart the app."
                }
            }
        }
    }

    private func grantAccessibility() {
        permissionMessage = "Repairing Accessibility permission..."
        permissionManager.resetPermission(.accessibility) { _ in
            let granted = AccessibilityPermissions.checkAccessibilityPermissions(prompt: true)
            refreshPermissions()
            if granted {
                permissionMessage = "Accessibility is granted."
            } else {
                permissionMessage = "Enable MoodleLens in Accessibility, then refresh."
            }
        }
    }

    private var browserContextDetail: String {
        let suffix = "Last: \(browserContextStatus)"
        if let browserName = BrowserContextProvider.automationTargetNameForSettings() {
            let detail = browserContextAllowed
                ? "\(browserName) can provide compact Moodle page context for Ask prompts. Chrome-family browsers must allow JavaScript from Apple Events."
                : "Grant Automation for \(browserName), then keep that browser focused when using Moodle Ask. Chrome-family browsers must allow JavaScript from Apple Events."
            return "\(detail) \(suffix)"
        }
        return "Optional. Open Chrome, Arc, Edge, Brave, or Chromium before granting. \(suffix)"
    }

    private func grantBrowserContext() {
        guard BrowserContextProvider.automationTargetNameForSettings() != nil else {
            permissionMessage = "Open a supported browser, then try again."
            return
        }

        permissionMessage = "Repairing Browser Context permission..."
        BrowserContextProvider.resetAutomationPermission { _ in
            let granted = BrowserContextProvider.requestAutomationForFrontmostBrowser()
            refreshPermissions()
            if granted {
                permissionMessage = "Browser Context is granted."
            } else {
                permissionMessage = "Enable MoodleLens under Automation for the browser, then refresh."
            }
        }
    }

    private func refreshCodexStatus() {
        isRefreshingCodexStatus = true
        DispatchQueue.global(qos: .userInitiated).async {
            let status = CodexCLIClient.currentStatus()
            DispatchQueue.main.async {
                codexStatus = status
                isRefreshingCodexStatus = false
            }
        }
    }

    private func openScreenRecordingSettings() {
        permissionManager.openSystemSettings(for: .screenCapture)
    }

    private func openAccessibilitySettings() {
        permissionManager.openSystemSettings(for: .accessibility)
    }

    private func uninstallMoodleLens() {
        do {
            let scriptURL = try MoodleLensUninstaller.writeScript()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            task.arguments = [
                "/bin/sh",
                scriptURL.path,
                "\(ProcessInfo.processInfo.processIdentifier)",
                Bundle.main.bundlePath
            ]
            if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
                task.standardOutput = devNull
                task.standardError = devNull
            }
            try task.run()
            NSApp.terminate(nil)
        } catch {
            validationMessage = "Could not start uninstall: \(error.localizedDescription)"
        }
    }
}

enum MoodleLensUninstaller {
    static func writeScript() throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moodlelens-uninstall-\(UUID().uuidString).sh")
        guard let data = script.data(using: .utf8) else {
            throw NSError(domain: "MoodleLensUninstaller", code: 1)
        }
        try data.write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static let script = #"""
#!/bin/sh
set +e

pid="$1"
app="$2"
bundle_id="io.github.volodymyryelisieiev.moodlelens"
keychain_account="openai_api_key"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1

tries=0
while kill -0 "$pid" 2>/dev/null && [ "$tries" -lt 50 ]; do
  sleep 0.2
  tries=$((tries + 1))
done
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" >/dev/null 2>&1
  sleep 0.5
fi
if kill -0 "$pid" 2>/dev/null; then
  kill -9 "$pid" >/dev/null 2>&1
fi

[ -x "$lsregister" ] && [ -d "$app" ] && "$lsregister" -u "$app" >/dev/null 2>&1
[ -x "$lsregister" ] && [ -d "/Applications/MoodleLens.app" ] && "$lsregister" -u "/Applications/MoodleLens.app" >/dev/null 2>&1
[ -x "$lsregister" ] && [ -d "$HOME/Applications/MoodleLens.app" ] && "$lsregister" -u "$HOME/Applications/MoodleLens.app" >/dev/null 2>&1

rm -rf "$app" \
  "/Applications/MoodleLens.app" \
  "$HOME/Applications/MoodleLens.app" \
  "$HOME/Library/Application Support/$bundle_id" \
  "$HOME/Library/Caches/$bundle_id" \
  "$HOME/Library/Containers/$bundle_id" \
  "$HOME/Library/HTTPStorages/$bundle_id" \
  "$HOME/Library/Saved Application State/$bundle_id.savedState" \
  "$HOME/Library/Preferences/$bundle_id.plist" \
  "$HOME/Library/Logs/$bundle_id" \
  "$HOME/Library/Logs/MoodleLens"*

rm -f "$HOME/Library/Preferences/ByHost/$bundle_id".*.plist
defaults delete "$bundle_id" >/dev/null 2>&1
security delete-generic-password -s "$bundle_id" -a "$keychain_account" >/dev/null 2>&1
rm -rf "${TMPDIR%/}/$bundle_id"
cache_root="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)"
[ -n "$cache_root" ] && rm -rf "${cache_root%/}/$bundle_id"
find /tmp -maxdepth 3 -user "$(id -un)" \( -iname '*moodlelens*' -o -name "$bundle_id" \) -exec rm -rf {} + 2>/dev/null

tccutil reset ScreenCapture "$bundle_id" >/dev/null 2>&1
tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1
tccutil reset ListenEvent "$bundle_id" >/dev/null 2>&1
tccutil reset AppleEvents "$bundle_id" >/dev/null 2>&1

rm -f "$0"
"""#
}
