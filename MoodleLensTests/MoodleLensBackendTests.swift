import Foundation
import AppKit
import XCTest
@testable import MoodleLens

final class MoodleLensBackendTests: XCTestCase {
    private var keychainStores: [KeychainCredentialStore] = []
    private var defaultsSuites: [String] = []

    override func tearDown() {
        for store in keychainStores {
            _ = store.delete()
        }
        for suite in defaultsSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        _ = TempFileManager.shared.cleanupAllTempFiles()
        super.tearDown()
    }

    func testSettingsProviderAndKeychainUseIsolatedStores() {
        let defaults = makeDefaults()
        let store = makeKeychainStore()
        let notifications = SpyNotificationService()

        let settings = SettingsManager(
            notificationService: notifications,
            userDefaults: defaults,
            keychainStore: store
        )

        XCTAssertEqual(settings.aiProvider, .openAIAPI)
        XCTAssertEqual(settings.openAIModel, AIModelDefaults.openAIModel)
        XCTAssertEqual(settings.codexReasoningEffort, AIModelDefaults.codexReasoningEffort)
        settings.aiProvider = .codexCLI
        settings.openAIModel = "gpt-5"
        settings.openAIReasoningEffort = "high"
        settings.openAISpeed = "priority"
        settings.codexModel = "gpt-5-codex"
        settings.codexReasoningEffort = "low"

        let reloaded = SettingsManager(
            notificationService: notifications,
            userDefaults: defaults,
            keychainStore: store
        )
        XCTAssertEqual(reloaded.aiProvider, .codexCLI)
        XCTAssertEqual(reloaded.openAIModel, "gpt-5")
        XCTAssertEqual(reloaded.openAIReasoningEffort, "high")
        XCTAssertEqual(reloaded.openAISpeed, "priority")
        XCTAssertEqual(reloaded.codexModel, "gpt-5-codex")
        XCTAssertEqual(reloaded.codexReasoningEffort, "low")

        XCTAssertTrue(settings.updateAPIKey("test-secret"))
        XCTAssertEqual(settings.apiKey, "test-secret")
        XCTAssertNil(defaults.string(forKey: "openai_api_key"))

        settings.resetAll()
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.aiProvider, .openAIAPI)
        XCTAssertEqual(settings.openAIModel, AIModelDefaults.openAIModel)
        XCTAssertEqual(settings.openAISpeed, AIModelDefaults.openAISpeed)
        XCTAssertEqual(settings.codexModel, AIModelDefaults.codexModel)
        XCTAssertTrue(notifications.posts.isEmpty)
    }

    func testSettingsPreserveUnknownProviderOptionsForManualRepair() {
        let defaults = makeDefaults()
        let settings = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )

        settings.openAIReasoningEffort = "future-reasoning"
        settings.openAISpeed = "future-tier"
        settings.codexReasoningEffort = "future-codex-reasoning"
        settings.codexSpeed = "future-codex-tier"

        let reloaded = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )
        XCTAssertEqual(reloaded.openAIReasoningEffort, "future-reasoning")
        XCTAssertEqual(reloaded.openAISpeed, "future-tier")
        XCTAssertEqual(reloaded.codexReasoningEffort, "future-codex-reasoning")
        XCTAssertEqual(reloaded.codexSpeed, "future-codex-tier")
    }

    func testKeychainStoreSaveReadUpdateDeleteIsIdempotent() {
        let store = makeKeychainStore()

        XCTAssertEqual(store.read().status, errSecItemNotFound)
        XCTAssertEqual(store.save("one"), errSecSuccess)
        XCTAssertEqual(store.read().value, "one")
        XCTAssertEqual(store.save("two"), errSecSuccess)
        XCTAssertEqual(store.read().value, "two")
        XCTAssertEqual(store.delete(), errSecSuccess)
        XCTAssertEqual(store.delete(), errSecSuccess)
        XCTAssertNil(store.read().value)
    }

    func testSettingsDoesNotMigrateAPIKeyFromUserDefaults() {
        let defaults = makeDefaults()
        defaults.set("old-secret", forKey: "openai_api_key")
        let settings = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )

        XCTAssertEqual(settings.apiKey, "")
    }

    func testAppearanceModeDefaultsPersistsAndResets() {
        let defaults = makeDefaults()
        let settings = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )

        XCTAssertEqual(settings.appearanceMode, .system)
        settings.appearanceMode = .dark

        let reloaded = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )
        XCTAssertEqual(reloaded.appearanceMode, .dark)

        reloaded.resetAll()
        XCTAssertEqual(reloaded.appearanceMode, .system)
    }

    func testInstructionsAreOneSharedContext() {
        let settings = makeSettings()

        XCTAssertEqual(settings.position, SettingsManager.defaultInstructions)
        XCTAssertTrue(settings.position.contains("Answer Moodle assessment tasks"))
        XCTAssertEqual(settings.screenshotContext, settings.position)
        XCTAssertEqual(settings.textContext, settings.position)

        settings.screenshotContext = "Custom Ask instructions"
        XCTAssertEqual(settings.position, "Custom Ask instructions")
        XCTAssertEqual(settings.textContext, "Custom Ask instructions")

        settings.textContext = "Shared instructions"
        XCTAssertEqual(settings.position, "Shared instructions")
        XCTAssertEqual(settings.screenshotContext, "Shared instructions")
    }

    func testHotkeyBindingsAndAskSettingsPersistAndReset() {
        let defaults = makeDefaults()
        let settings = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )

        XCTAssertEqual(AppHotkey.registeredHotkeys, [.openSettings, .ask, .toggleBubble, .clearChat])
        XCTAssertEqual(AppHotkey.openSettings.defaultBinding, HotkeyBinding(keyCode: 5, modifiers: HotkeyBinding.option))
        XCTAssertEqual(AppHotkey.ask.defaultBinding, HotkeyBinding(keyCode: 0, modifiers: HotkeyBinding.option))
        XCTAssertEqual(AppHotkey.toggleBubble.defaultBinding, HotkeyBinding(keyCode: 11, modifiers: HotkeyBinding.option))
        XCTAssertEqual(AppHotkey.clearChat.defaultBinding, HotkeyBinding(keyCode: 8, modifiers: HotkeyBinding.option))
        XCTAssertEqual(settings.hotkeyBinding(for: .ask), AppHotkey.ask.defaultBinding)
        let customBinding = HotkeyBinding(keyCode: 0, modifiers: HotkeyBinding.command | HotkeyBinding.option)
        settings.setHotkeyBinding(customBinding, for: .openSettings)
        settings.askCorner = .topLeft
        settings.askOpacity = 0.2

        let reloaded = SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: defaults,
            keychainStore: makeKeychainStore()
        )
        XCTAssertEqual(reloaded.hotkeyBinding(for: .openSettings), customBinding)
        XCTAssertEqual(reloaded.askCorner, .topLeft)
        XCTAssertEqual(reloaded.askOpacity, 0.35)

        reloaded.resetAll()
        XCTAssertEqual(reloaded.hotkeyBinding(for: .openSettings), AppHotkey.openSettings.defaultBinding)
        XCTAssertEqual(reloaded.askCorner, .bottomRight)
        XCTAssertEqual(reloaded.askOpacity, 0.75)
    }

    func testBrowserContextCompactsUsefulDomWithoutRawHtmlOrPasswords() throws {
        let hidden = String(repeating: "hidden-token ", count: 2_000)
        let object: [String: Any] = [
            "url": "https://example.test/form",
            "title": "Example",
            "text": hidden,
            "inputs": ["Email | email | user@example.test", "Password | password | secret"],
            "buttons": ["Submit"],
            "selects": ["Plan: Free / Pro / Enterprise"],
            "controls": ["combobox | expanded=false | Plan"],
            "datalists": ["Cities: Vienna / Kyiv"],
            "options": ["Dropdown A", "Dropdown B"],
            "links": ["Docs"]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let context = try XCTUnwrap(BrowserContextProvider.compactContext(from: json, browserName: "Chrome"))

        XCTAssertLessThanOrEqual(context.count, 12_000)
        XCTAssertTrue(context.contains("Select Options"))
        XCTAssertTrue(context.contains("Free / Pro / Enterprise"))
        XCTAssertTrue(context.contains("Controls"))
        XCTAssertTrue(context.contains("Cities: Vienna / Kyiv"))
        XCTAssertFalse(context.contains("<html"))
        XCTAssertFalse(context.contains("secret"))
    }

    func testBrowserContextDetectsMoodleTasksAndRejectsMissingEvidence() throws {
        let moodleQuestionJSON = try jsonString([
            "url": "https://moodle.jku.at/mod/quiz/attempt.php?attempt=1",
            "title": "Quiz attempt",
            "generator": "Moodle",
            "moodleConfig": true,
            "text": "Question 1 Answer all parts of this quiz.",
            "moodleQuestions": ["Question 1: What is supervised learning? Answer the question."],
            "moodleActivities": []
        ])
        guard case .attached(let context) = BrowserContextProvider.contextResult(from: moodleQuestionJSON, browserName: "Chrome") else {
            XCTFail("Expected Moodle context")
            return
        }
        XCTAssertTrue(context.contains("Moodle Questions"))
        XCTAssertTrue(context.contains("supervised learning"))

        let nonMoodleJSON = try jsonString([
            "url": "https://example.test/mod/quiz/looks-similar",
            "title": "Example",
            "text": "Question 1 on a non Moodle page."
        ])
        XCTAssertEqual(
            BrowserContextProvider.contextResult(from: nonMoodleJSON, browserName: "Chrome"),
            .failure(.nonMoodlePage)
        )

        let moodleArticleJSON = try jsonString([
            "url": "https://example.test/articles/moodle-quiz-agent-demo",
            "title": "Moodle quiz article",
            "text": "Question 1 Answer this example quiz attempt from an article about Moodle."
        ])
        XCTAssertEqual(
            BrowserContextProvider.contextResult(from: moodleArticleJSON, browserName: "Chrome"),
            .failure(.nonMoodlePage)
        )

        let fakeHostJSON = try jsonString([
            "url": "https://notmoodle.example/mod/quiz/attempt.php",
            "title": "Quiz attempt",
            "text": "Question 1 Answer this non Moodle page."
        ])
        XCTAssertEqual(
            BrowserContextProvider.contextResult(from: fakeHostJSON, browserName: "Chrome"),
            .failure(.nonMoodlePage)
        )

        let noTaskJSON = try jsonString([
            "url": "https://qa.moodledemo.net/",
            "title": "Moodle dashboard",
            "generator": "Moodle",
            "moodleConfig": true,
            "text": "Dashboard Calendar Private files",
            "moodleQuestions": [],
            "moodleActivities": []
        ])
        XCTAssertEqual(
            BrowserContextProvider.contextResult(from: noTaskJSON, browserName: "Chrome"),
            .failure(.noExtractableMoodleTask)
        )
        XCTAssertEqual(BrowserContextProvider.FailureReason.noExtractableMoodleTask.rawValue, "no_task_found")
        XCTAssertEqual(
            BrowserContextProvider.snapshotFailureReason(for: "Executing JavaScript through AppleScript is turned off. Enable Allow JavaScript from Apple Events."),
            .javascriptFromAppleEventsDisabled
        )
    }

    func testBrowserContextFormatsStructuredMoodleEvidenceForQuestionTypes() throws {
        let object: [String: Any] = [
            "url": "https://qa.moodledemo.net/mod/quiz/attempt.php",
            "title": "Moodle quiz",
            "generator": "Moodle",
            "moodleConfig": true,
            "moodleCourse": "AI Fundamentals",
            "moodleActivity": "Week 2 quiz",
            "text": "Question 1 Question 2 Question 3 Assignment instructions",
            "moodleTasks": [
                [
                    "id": "question-1",
                    "type": "single_choice",
                    "questionText": "Choose the supervised learning example.",
                    "options": [
                        ["text": "Linear regression", "value": "A", "selected": true, "control": "radio"],
                        ["text": "K-means", "value": "B", "selected": false, "control": "radio"]
                    ],
                    "feedback": "",
                    "controls": ["Next page"]
                ],
                [
                    "id": "question-2",
                    "type": "multiple_choice",
                    "questionText": "Select all neural network layers.",
                    "options": [
                        ["text": "Dense", "value": "dense", "selected": true, "control": "checkbox"],
                        ["text": "Optimizer", "value": "optimizer", "selected": false, "control": "checkbox"]
                    ],
                    "feedback": "Partially correct",
                    "controls": []
                ],
                [
                    "id": "question-3",
                    "type": "select",
                    "questionText": "Pick the activation function.",
                    "options": [
                        ["text": "Activation: ReLU", "value": "relu", "selected": true, "control": "select"]
                    ],
                    "feedback": "",
                    "controls": []
                ],
                [
                    "id": "question-4",
                    "type": "short_answer",
                    "questionText": "Name one loss function.",
                    "options": [
                        ["text": "answer | MSE", "value": "MSE", "selected": true, "control": "input"]
                    ],
                    "feedback": "",
                    "controls": []
                ],
                [
                    "id": "assignment-1",
                    "type": "assignment",
                    "questionText": "Submit a short reflection about model evaluation by Friday.",
                    "options": [],
                    "feedback": "",
                    "controls": ["Submit assignment"]
                ]
            ]
        ]
        guard case .attached(let context) = BrowserContextProvider.contextResult(
            from: try jsonString(object),
            browserName: "Chrome"
        ) else {
            XCTFail("Expected structured Moodle context")
            return
        }

        XCTAssertTrue(context.contains("Course: AI Fundamentals"))
        XCTAssertTrue(context.contains("Activity: Week 2 quiz"))
        XCTAssertTrue(context.contains("question-1 [single_choice]"))
        XCTAssertTrue(context.contains("* Linear regression (A)"))
        XCTAssertTrue(context.contains("question-2 [multiple_choice]"))
        XCTAssertTrue(context.contains("Feedback: Partially correct"))
        XCTAssertTrue(context.contains("question-3 [select]"))
        XCTAssertTrue(context.contains("question-4 [short_answer]"))
        XCTAssertTrue(context.contains("assignment-1 [assignment]"))
        XCTAssertTrue(context.contains("Controls: Submit assignment"))
    }

    func testTempFileManagerCreateDeleteAndCleanupAreIdempotent() throws {
        let manager = TempFileManager.shared
        _ = manager.cleanupAllTempFiles()

        let fileURL = manager.createTempFileURL(prefix: "Test-\(UUID().uuidString)", extension: "txt")
        try "temporary".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        XCTAssertTrue(manager.deleteTempFile(fileURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(manager.deleteTempFile(fileURL))

        let cleanupURL = manager.createTempFileURL(prefix: "Cleanup-\(UUID().uuidString)", extension: "txt")
        try "temporary".write(to: cleanupURL, atomically: true, encoding: .utf8)
        XCTAssertGreaterThanOrEqual(manager.cleanupAllTempFiles(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupURL.path))
        XCTAssertEqual(manager.cleanupAllTempFiles(), 0)
    }

    func testCodexArgumentsUseStrictEphemeralModelReasoningImageAndPromptSeparator() {
        let imageURL = URL(fileURLWithPath: "/tmp/moodlelens-image.png")
        let outputURL = URL(fileURLWithPath: "/tmp/moodlelens-output.txt")
        let args = CodexCLIClient.buildArguments(
            prompt: "answer this",
            imageURL: imageURL,
            outputURL: outputURL,
            model: AIModelDefaults.codexModel,
            reasoningEffort: AIModelDefaults.codexReasoningEffort,
            speed: "fast"
        )

        XCTAssertEqual(args.prefix(2), ["exec", "--ephemeral"])
        XCTAssertTrue(args.contains("--ignore-user-config"))
        XCTAssertTrue(args.contains("--strict-config"))
        XCTAssertPair(args, "--model", AIModelDefaults.codexModel)
        XCTAssertPair(args, "-c", "model_reasoning_effort=\"\(AIModelDefaults.codexReasoningEffort)\"")
        XCTAssertPair(args, "--sandbox", "read-only")
        XCTAssertPair(args, "--output-last-message", outputURL.path)
        XCTAssertPair(args, "-i", imageURL.path)
        XCTAssertFalse(args.contains("service_tier=\"fast\""))
        XCTAssertEqual(args.suffix(2), ["--", "answer this"])
    }

    func testOpenAIModelCatalogParsesTextModelIDsAndKeepsSelectedFallback() throws {
        let payload = """
        {
          "object": "list",
          "data": [
            { "id": "text-embedding-3-large" },
            { "id": "gpt-5-mini" },
            { "id": "o4-mini" },
            { "id": "dall-e-3" },
            { "id": "gpt-5-mini" }
          ]
        }
        """
        let ids = try OpenAIModelCatalog.parseModelIDs(from: XCTUnwrap(payload.data(using: .utf8)))

        XCTAssertEqual(ids, ["gpt-5-mini", "o4-mini"])
        XCTAssertEqual(
            OpenAIModelCatalog.mergedModelIDs(ids, selected: "custom-live-model"),
            ["custom-live-model", "gpt-5-mini", "o4-mini"]
        )
    }

    func testCodexModelCatalogParsesVisibleModelSlugsAndKeepsSelectedFallback() throws {
        let payload = """
        {
          "models": [
            { "slug": "gpt-5.5", "visibility": "list" },
            { "slug": "codex-auto-review", "visibility": "hide" },
            { "slug": "gpt-5.4-mini", "visibility": "list" },
            { "slug": "gpt-5.5", "visibility": "list" }
          ]
        }
        """
        let ids = try CodexModelCatalog.parseModelIDs(from: XCTUnwrap(payload.data(using: .utf8)))

        XCTAssertEqual(ids, ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(
            CodexModelCatalog.mergedModelIDs(ids, selected: "custom-codex-model"),
            ["custom-codex-model", "gpt-5.5", "gpt-5.4-mini"]
        )
    }

    func testOpenAIRequestBuilderMapsReasoningAndServiceTierOnlyWhenAccepted() {
        let messages: [[String: String]] = [["role": "user", "content": "hello"]]
        let reasoningBody = OpenAIRequestBuilder.requestBody(
            model: "gpt-5",
            messages: messages,
            reasoningEffort: "high",
            serviceTier: AIModelDefaults.openAISpeed
        )
        XCTAssertEqual(reasoningBody["reasoning_effort"] as? String, "high")
        XCTAssertNil(reasoningBody["service_tier"])

        let tierBody = OpenAIRequestBuilder.requestBody(
            model: "gpt-4.1",
            messages: messages,
            reasoningEffort: "high",
            serviceTier: "priority"
        )
        XCTAssertNil(tierBody["reasoning_effort"])
        XCTAssertEqual(tierBody["service_tier"] as? String, "priority")
    }

    func testOpenAIClientRoutesCodexProviderToInjectedClientWithoutRealCLI() {
        let settings = makeSettings()
        settings.aiProvider = .codexCLI
        let codex = FakeCodexClient()
        let notifications = SpyNotificationService()
        let client = OpenAIClient(
            settingsManager: settings,
            notificationService: notifications,
            codexClient: codex
        )

        XCTAssertTrue(client.isConfigured())
        let expectation = expectation(description: "Codex response")
        client.sendRequest(prompt: "hello") { result in
            XCTAssertEqual(try? result.get(), "codex-ok")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(codex.textPrompts, ["hello"])
    }

    func testOpenAIClientOpenAIProviderFailsMissingKeyWithoutCodexCall() {
        let settings = makeSettings()
        settings.aiProvider = .openAIAPI
        XCTAssertTrue(settings.updateAPIKey(""))
        let codex = FakeCodexClient()
        let client = OpenAIClient(
            settingsManager: settings,
            notificationService: SpyNotificationService(),
            codexClient: codex
        )

        XCTAssertFalse(client.isConfigured())
        let expectation = expectation(description: "Missing key failure")
        client.sendRequest(prompt: "hello") { result in
            guard case .failure(let error) = result else {
                XCTFail("Expected missing-key failure")
                expectation.fulfill()
                return
            }
            XCTAssertEqual((error as NSError).domain, "OpenAIClient")
            XCTAssertEqual((error as NSError).code, 401)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(codex.textPrompts.isEmpty)
    }

    func testConfiguredLaunchStaysBackgroundOnlyAndFirstRunShowsSetup() {
        let configuredClient = FakeOpenAIClient()
        configuredClient.hasApiKey = true
        XCTAssertFalse(AppDelegate.shouldShowSettingsOnLaunch(openAIClient: configuredClient))

        let unconfiguredClient = FakeOpenAIClient()
        unconfiguredClient.hasApiKey = false
        XCTAssertTrue(AppDelegate.shouldShowSettingsOnLaunch(openAIClient: unconfiguredClient))
    }

    func testSettingsShortcutClosesOnlyWhenSettingsAlreadyHasFocus() {
        XCTAssertTrue(AppDelegate.shouldCloseSettingsWindow(isKeyWindow: true))
        XCTAssertFalse(AppDelegate.shouldCloseSettingsWindow(isKeyWindow: false))
    }

    @MainActor
    func testAssistantWindowIsCaptureExcludedAndHiddenFromWindowLists() {
        let manager = WindowManager(notificationService: SpyNotificationService())
        let window = manager.createTransparentWindow()
        defer { window.orderOut(nil) }

        XCTAssertEqual(window.sharingType, .none)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @MainActor
    func testSettingsWindowIsCaptureExcludedAndHiddenFromWindowLists() throws {
        let notifications = SpyNotificationService()
        let appDelegate = AppDelegate(
            windowManager: WindowManager(notificationService: notifications),
            openAIClient: FakeOpenAIClient(),
            screenshotService: FakeScreenshotService(),
            permissionManager: FakePermissionManager(),
            notificationService: notifications,
            viewFactory: ViewFactory()
        )

        appDelegate.showSettings()
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Settings" })
        defer { window.orderOut(nil) }

        XCTAssertEqual(window.sharingType, .none)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testAskCodexImageRequestDoesNotPostNormalChatNotification() throws {
        let settings = makeSettings()
        settings.aiProvider = .codexCLI
        let codex = FakeCodexClient()
        let notifications = SpyNotificationService()
        let client = OpenAIClient(
            settingsManager: settings,
            notificationService: notifications,
            codexClient: codex
        )
        let imageURL = TempFileManager.shared.createTempFileURL(prefix: "AskTest", extension: "png")
        try Data("png".utf8).write(to: imageURL)
        defer { TempFileManager.shared.deleteTempFile(imageURL) }

        let expectation = expectation(description: "Ask image response")
        client.sendImageRequest(imageURL: imageURL, prompt: "ask", contextInfo: ["source": AskController.source]) { result in
            XCTAssertEqual(try? result.get(), "codex-image-ok")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(codex.imagePrompts.map(\.prompt), ["ask"])
        XCTAssertFalse(notifications.posts.contains { $0.name == .openAIResponseReceived })
    }

    @MainActor
    func testAskBubbleIsCaptureExcludedTransientAndHiddenFromWindowLists() throws {
        let screenshotService = FakeScreenshotService()
        let notifications = SpyNotificationService()
        let ask = AskController(
            openAIClient: FakeOpenAIClient(),
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(),
            notificationService: notifications,
            browserContextProvider: { $0 }
        )

        ask.ask()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let context = try XCTUnwrap(screenshotService.capturedContexts.first)
        let requestID = try XCTUnwrap(context["requestID"] as? String)
        let imageURL = TempFileManager.shared.createTempFileURL(prefix: "AskBubbleSecurity", extension: "png")
        try Data("png".utf8).write(to: imageURL)
        notifications.post(
            name: .screenshotCaptured,
            object: [
                "source": AskController.source,
                "requestID": requestID,
                "path": imageURL.path,
                BrowserContextProvider.contextInfoKey: "Moodle Structured Tasks:\n- question-1 [single_choice]: Demo question"
            ]
        )

        waitUntil("ask bubble window") {
            askBubbleWindow() != nil
        }
        let window = try XCTUnwrap(askBubbleWindow())
        defer { ask.clearHistory() }

        XCTAssertEqual(window.sharingType, .none)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertTrue(window.collectionBehavior.contains(.transient))
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @MainActor
    func testAskTriggerUsesDeferredTaggedScreenshotCaptureAndClearsHistory() throws {
        let screenshotService = FakeScreenshotService()
        let notifications = SpyNotificationService()
        let ask = AskController(
            openAIClient: FakeOpenAIClient(),
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(),
            notificationService: notifications,
            browserContextProvider: { $0 }
        )

        ask.ask()
        waitUntil("screenshot context") { !screenshotService.capturedContexts.isEmpty }

        XCTAssertEqual(screenshotService.capturedContexts.count, 1)
        let context = try XCTUnwrap(screenshotService.capturedContexts.first)
        XCTAssertEqual(context["source"] as? String, AskController.source)
        XCTAssertEqual(context["deferAnalysis"] as? Bool, true)
        let requestID = try XCTUnwrap(context["requestID"] as? String)

        let imageURL = TempFileManager.shared.createTempFileURL(prefix: "AskCaptured", extension: "png")
        try Data("png".utf8).write(to: imageURL)
        notifications.post(
            name: .screenshotCaptured,
            object: [
                "source": AskController.source,
                "requestID": requestID,
                "path": imageURL.path,
                BrowserContextProvider.contextInfoKey: "Moodle Structured Tasks:\n- question-1 [single_choice]: Demo question"
            ]
        )

        waitUntil("ask history") { ask.historyCount == 2 }
        let snapshot = ask.sessionHistorySnapshot()
        XCTAssertEqual(snapshot.map(\.type), [.user, .assistant])
        XCTAssertEqual(snapshot.map(\.text), ["Screenshot", "fake-image"])
        XCTAssertTrue(notifications.posts.contains { $0.name == AskController.historyDidChange })

        ask.clearHistory()
        XCTAssertEqual(ask.historyCount, 0)
        XCTAssertTrue(ask.sessionHistorySnapshot().isEmpty)
        XCTAssertGreaterThanOrEqual(notifications.posts.filter { $0.name == AskController.historyDidChange }.count, 2)
    }

    @MainActor
    func testToggleBubbleDoesNotScheduleAutoHideForLastAnswer() throws {
        let screenshotService = FakeScreenshotService()
        let notifications = SpyNotificationService()
        let ask = AskController(
            openAIClient: FakeOpenAIClient(),
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(),
            notificationService: notifications,
            browserContextProvider: { $0 }
        )
        defer { ask.clearHistory() }

        ask.ask()
        waitUntil("screenshot context") { !screenshotService.capturedContexts.isEmpty }

        let context = try XCTUnwrap(screenshotService.capturedContexts.first)
        let requestID = try XCTUnwrap(context["requestID"] as? String)
        let imageURL = TempFileManager.shared.createTempFileURL(prefix: "AskToggle", extension: "png")
        try Data("png".utf8).write(to: imageURL)
        notifications.post(
            name: .screenshotCaptured,
            object: [
                "source": AskController.source,
                "requestID": requestID,
                "path": imageURL.path,
                BrowserContextProvider.contextInfoKey: "Moodle Structured Tasks:\n- question-1 [single_choice]: Demo question"
            ]
        )

        waitUntil("ask auto-hide scheduled") {
            ask.historyCount == 2 && ask.isBubbleVisibleForTesting && ask.isAutoHideScheduledForTesting
        }

        ask.toggleBubble()
        XCTAssertFalse(ask.isBubbleVisibleForTesting)
        XCTAssertFalse(ask.isAutoHideScheduledForTesting)

        ask.toggleBubble()
        XCTAssertTrue(ask.isBubbleVisibleForTesting)
        XCTAssertFalse(ask.isAutoHideScheduledForTesting)

        ask.toggleBubble()
        XCTAssertFalse(ask.isBubbleVisibleForTesting)
        XCTAssertFalse(ask.isAutoHideScheduledForTesting)
    }

    @MainActor
    func testAskScreenshotPromptIncludesBrowserSnapshotContext() throws {
        let screenshotService = FakeScreenshotService()
        let notifications = SpyNotificationService()
        let openAI = FakeOpenAIClient()
        let ask = AskController(
            openAIClient: openAI,
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(),
            notificationService: notifications,
            browserContextProvider: { contextInfo in
                var updated = contextInfo ?? [:]
                updated[BrowserContextProvider.contextInfoKey] = "URL: https://example.test\nSelect Options:\n- Free\n- Pro"
                return updated
            }
        )
        defer { ask.clearHistory() }

        ask.ask()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let capturedContext = try XCTUnwrap(screenshotService.capturedContexts.first)
        let imageURL = TempFileManager.shared.createTempFileURL(prefix: "AskBrowserContext", extension: "png")
        try Data("png".utf8).write(to: imageURL)
        var payload = capturedContext
        payload["path"] = imageURL.path
        notifications.post(
            name: .screenshotCaptured,
            object: payload
        )

        waitUntil("browser context prompt") { openAI.imageRequests.isEmpty == false }
        waitUntil("ask response cleanup point") { ask.historyCount == 2 }
        let prompt = try XCTUnwrap(openAI.imageRequests.first?.prompt)
        XCTAssertTrue(prompt.contains("Browser snapshot from the current active webpage"))
        XCTAssertTrue(prompt.contains("Screenshot evidence: Current display/viewport screenshot"))
        XCTAssertTrue(prompt.contains("Answer only from the screenshot and parsed Moodle tasks"))
        XCTAssertTrue(prompt.contains("If multiple Moodle tasks/questions are present"))
        XCTAssertTrue(prompt.contains("https://example.test"))
        XCTAssertTrue(prompt.contains("Pro"))
    }

    @MainActor
    func testAskStopsAfterScreenshotWhenParsedMoodleEvidenceIsMissing() throws {
        let screenshotService = FakeScreenshotService()
        let notifications = SpyNotificationService()
        let openAI = FakeOpenAIClient()
        let ask = AskController(
            openAIClient: openAI,
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(),
            notificationService: notifications,
            browserContextProvider: { $0 }
        )

        ask.ask()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let capturedContext = try XCTUnwrap(screenshotService.capturedContexts.first)
        let requestID = try XCTUnwrap(capturedContext["requestID"] as? String)
        let imageURL = TempFileManager.shared.createTempFileURL(prefix: "AskMissingMoodleEvidence", extension: "png")
        try Data("png".utf8).write(to: imageURL)
        notifications.post(
            name: .screenshotCaptured,
            object: ["source": AskController.source, "requestID": requestID, "path": imageURL.path]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        defer { ask.clearHistory() }

        XCTAssertTrue(openAI.imageRequests.isEmpty)
        XCTAssertEqual(ask.lastBubbleTextForTesting, BrowserContextProvider.FailureReason.noExtractableMoodleTask.userMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    }

    @MainActor
    func testAskStopsBeforeScreenshotWhenBrowserContextFails() {
        let screenshotService = FakeScreenshotService()
        let reason = BrowserContextProvider.FailureReason.nonMoodlePage
        let ask = AskController(
            openAIClient: FakeOpenAIClient(),
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(),
            notificationService: SpyNotificationService(),
            browserContextProvider: { contextInfo in
                var updated = contextInfo ?? [:]
                updated[BrowserContextProvider.failureReasonKey] = reason.rawValue
                updated[BrowserContextProvider.failureMessageKey] = reason.userMessage
                return updated
            }
        )

        ask.ask()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        defer { ask.clearHistory() }

        XCTAssertTrue(screenshotService.capturedContexts.isEmpty)
        XCTAssertEqual(ask.lastBubbleTextForTesting, reason.userMessage)
    }

    @MainActor
    func testAskScreenPermissionSkipDoesNotCapture() {
        let screenshotService = FakeScreenshotService()
        let ask = AskController(
            openAIClient: FakeOpenAIClient(),
            screenshotService: screenshotService,
            permissionManager: FakePermissionManager(screenStatus: .denied),
            notificationService: SpyNotificationService(),
            browserContextProvider: { $0 }
        )
        defer { ask.clearHistory() }

        ask.ask()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(screenshotService.capturedContexts.isEmpty)
    }

    func testScreenshotDeferredFlowPostsCapturedPathWithoutSendingToModel() throws {
        let openAI = FakeOpenAIClient()
        let notifications = SpyNotificationService()
        let service = ScreenshotService(
            openAIClient: openAI,
            notificationService: notifications,
            permissionManager: FakePermissionManager()
        )

        service.setContextInfo(["deferAnalysis": true])
        service.processScreenshot(makeTestImage())
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(openAI.imageRequests.isEmpty)
        let capturedPayload = notifications.posts
            .compactMap { $0.object as? [String: Any] }
            .first { $0["path"] != nil }
        let path = try XCTUnwrap(capturedPayload?["path"] as? String)
        XCTAssertEqual(capturedPayload?[ScreenshotService.screenshotScopeKey] as? String, ScreenshotService.screenshotScopeDisplayViewport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertGreaterThanOrEqual(TempFileManager.shared.cleanupAllTempFiles(), 1)
    }

    func testScreenshotSendFlowUsesPromptAndCleansTempFile() {
        let openAI = FakeOpenAIClient()
        let sent = expectation(description: "Screenshot sent to model")
        openAI.onImageRequest = { request in
            XCTAssertEqual(request.prompt, "Explain this")
            XCTAssertTrue(FileManager.default.fileExists(atPath: request.imageURL.path))
            sent.fulfill()
        }
        let service = ScreenshotService(
            openAIClient: openAI,
            notificationService: SpyNotificationService(),
            permissionManager: FakePermissionManager()
        )

        service.setContextInfo(["prompt": "Explain this"])
        service.processScreenshot(makeTestImage())
        wait(for: [sent], timeout: 1)

        let sentPath = openAI.imageRequests.first?.imageURL.path
        waitUntil("temporary screenshot is deleted") {
            guard let sentPath else { return false }
            return !FileManager.default.fileExists(atPath: sentPath)
        }
    }

    func testUserFacingErrorMessagesCoverConfiguredFailureModes() {
        XCTAssertEqual(
            AIServiceError.apiKeyMissing.localizedDescription,
            "OpenAI API key is missing. Open Settings and paste a valid key."
        )
        XCTAssertTrue(CodexCLIError.missingCLI.localizedDescription.contains("Codex CLI is not installed"))
        XCTAssertTrue(CodexCLIError.notAuthenticated.localizedDescription.contains("Codex CLI is not authenticated"))
        XCTAssertTrue(
            CodexCLIError.commandFailed(status: 1, details: "unsupported model gpt-5.5")
                .localizedDescription
                .contains(SettingsManager.shared.codexModel)
        )
        XCTAssertTrue(
            AIServiceError.permissionDenied(permission: "Screen Recording")
                .localizedDescription
                .contains("Screen Recording permission is required")
        )
        XCTAssertTrue(AIServiceError.imageTooLarge.localizedDescription.contains("too large"))

        let invalidReasoning = NSError(
            domain: "OpenAIClient",
            code: 400,
            userInfo: [
                NSLocalizedDescriptionKey: "HTTP Error: 400 - Unsupported parameter: reasoning_effort is not supported with this model"
            ]
        )
        XCTAssertEqual(
            AIServiceError.from(invalidReasoning).localizedDescription,
            "OpenAI rejected the selected model, reasoning, or speed setting. Open Settings, refresh models, and choose a supported provider configuration."
        )

        let missingModel = NSError(
            domain: "OpenAIClient",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "HTTP Error: 404 - model not found"]
        )
        XCTAssertTrue(AIServiceError.from(missingModel).localizedDescription.contains("Open Settings"))
    }

    func testMarkdownParserUsesNativeMarkdownWithUnicodeFallback() {
        XCTAssertEqual(String(MarkdownParser.parse(text: "**Bold** emoji 🧪 中文").characters), "Bold emoji 🧪 中文")
        XCTAssertEqual(String(MarkdownParser.parse(text: "A  B").characters), "A  B")
        XCTAssertEqual(String(MarkdownParser.parse(text: "[broken](<").characters), "[broken](<")
    }

    func testMessageParserPreservesVisibleWhitespace() {
        let contents = Message.parseTextForCodeBlocks("A  B  \n```text\n1\n```  \nC  D")
        XCTAssertEqual(contents.count, 3)
        XCTAssertEqual(contents[0].content, "A  B")
        XCTAssertEqual(contents[0].type, .text)
        XCTAssertEqual(contents[1].content, "1")
        XCTAssertEqual(contents[1].type, .code(language: "text"))
        XCTAssertEqual(contents[2].content, "C  D")
    }

    func testUninstallerScriptContainsFullCleanup() throws {
        let scriptURL = try MoodleLensUninstaller.writeScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("/Applications/MoodleLens.app"))
        XCTAssertTrue(script.contains("$HOME/Applications/MoodleLens.app"))
        XCTAssertTrue(script.contains("security delete-generic-password"))
        XCTAssertTrue(script.contains("defaults delete \"$bundle_id\""))
        XCTAssertTrue(script.contains("tccutil reset Accessibility"))
        XCTAssertTrue(script.contains("rm -f \"$0\""))
    }

    private func makeSettings() -> SettingsManager {
        SettingsManager(
            notificationService: SpyNotificationService(),
            userDefaults: makeDefaults(),
            keychainStore: makeKeychainStore()
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "io.github.volodymyryelisieiev.moodlelens.tests.\(UUID().uuidString)"
        defaultsSuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeKeychainStore() -> KeychainCredentialStore {
        let store = KeychainCredentialStore(
            service: "io.github.volodymyryelisieiev.moodlelens.tests.\(UUID().uuidString)",
            account: "openai_api_key"
        )
        keychainStores.append(store)
        _ = store.delete()
        return store
    }

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}

private func jsonString(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try XCTUnwrap(String(data: data, encoding: .utf8), file: file, line: line)
}

private final class SpyNotificationService: NotificationServiceProtocol {
    private(set) var posts: [(name: Notification.Name, object: Any?)] = []
    private var observers: [UUID: (name: Notification.Name?, handler: (Notification) -> Void)] = [:]

    func post(name: Notification.Name, object: Any?) {
        posts.append((name, object))
        for observer in observers.values where observer.name == nil || observer.name == name {
            observer.handler(Notification(name: name, object: object))
        }
    }

    func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {}

    func removeObserver(_ observer: Any) {
        if let token = observer as? ObserverToken {
            observers.removeValue(forKey: token.id)
        }
    }

    @discardableResult
    func addObserverForName(
        _ name: Notification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using handler: @escaping (Notification) -> Void
    ) -> NSObjectProtocol {
        let token = ObserverToken()
        observers[token.id] = (name, handler)
        return token
    }

    private final class ObserverToken: NSObject {
        let id = UUID()
    }
}

private final class FakeCodexClient: CodexCLIProviding {
    var isReady = true
    private(set) var textPrompts: [String] = []
    private(set) var imagePrompts: [(imageURL: URL, prompt: String)] = []
    var textResult: Result<String, Error> = .success("codex-ok")
    var imageResult: Result<String, Error> = .success("codex-image-ok")

    func sendTextRequest(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        textPrompts.append(prompt)
        completion(textResult)
    }

    func sendImageRequest(imageURL: URL, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        imagePrompts.append((imageURL, prompt))
        completion(imageResult)
    }
}

private final class FakeOpenAIClient: OpenAIClientProtocol {
    struct ImageRequest {
        let imageURL: URL
        let prompt: String
        let contextInfo: [String: Any]?
    }

    var hasApiKey = true
    private(set) var imageRequests: [ImageRequest] = []
    private(set) var contextRequests: [(prompt: String, contextMessages: [Message])] = []
    var onImageRequest: ((ImageRequest) -> Void)?

    func setAPIKey(_ key: String) {}

    func sendRequest(prompt: String) async throws -> String {
        "fake"
    }

    func sendRequestWithContext(prompt: String, contextMessages: [Message]) async throws -> String {
        contextRequests.append((prompt, contextMessages))
        return "fake"
    }

    func sendImageRequest(imageURL: URL, prompt: String, contextInfo: [String: Any]?) async throws -> String {
        let request = ImageRequest(imageURL: imageURL, prompt: prompt, contextInfo: contextInfo)
        imageRequests.append(request)
        onImageRequest?(request)
        return "fake-image"
    }

    func clearConversation() {}

    func isConfigured() -> Bool {
        hasApiKey
    }

    func sendRequest(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("fake"))
    }

    func sendRequestWithContext(prompt: String, contextMessages: [Message], completion: @escaping (Result<String, Error>) -> Void) {
        contextRequests.append((prompt, contextMessages))
        completion(.success("fake"))
    }

    func sendImageRequest(imageURL: URL, prompt: String, contextInfo: [String: Any]?, completion: @escaping (Result<String, Error>) -> Void) {
        let request = ImageRequest(imageURL: imageURL, prompt: prompt, contextInfo: contextInfo)
        imageRequests.append(request)
        onImageRequest?(request)
        completion(.success("fake-image"))
    }
}

private final class FakeScreenshotService: ScreenshotServiceProtocol {
    private(set) var capturedContexts: [[String: Any]] = []

    func setAppDelegate(_ delegate: AppDelegateProtocol) {}
    func setContextInfo(_ contextInfo: [String: Any]?) {}
    func captureScreenshot(contextInfo: [String: Any]?) -> Bool {
        capturedContexts.append(contextInfo ?? [:])
        return true
    }
    func analyzeScreenshot(at imageURL: URL, prompt: String, contextInfo: [String: Any]?) {}
}

private extension Message {
    var text: String {
        contents.map(\.content).joined(separator: "\n")
    }
}

private final class FakePermissionManager: PermissionManagerProtocol {
    var screenStatus: PermissionManager.PermissionStatus
    private(set) var resetPermissions: [PermissionManager.PermissionType] = []

    init(screenStatus: PermissionManager.PermissionStatus = .authorized) {
        self.screenStatus = screenStatus
    }

    func screenCapturePermissionStatus(completion: @escaping (PermissionManager.PermissionStatus) -> Void) {
        completion(screenStatus)
    }

    func requestScreenCapturePermission(completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func resetPermission(_ permissionType: PermissionManager.PermissionType, completion: @escaping (Bool) -> Void) {
        resetPermissions.append(permissionType)
        completion(true)
    }

    func openSystemSettings(for permissionType: PermissionManager.PermissionType) {}
}

private func XCTAssertPair(
    _ values: [String],
    _ key: String,
    _ value: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let index = values.firstIndex(of: key), values.index(after: index) < values.endIndex else {
        XCTFail("Missing argument pair for \(key)", file: file, line: line)
        return
    }
    XCTAssertEqual(values[values.index(after: index)], value, file: file, line: line)
}

@MainActor
private func askBubbleWindow() -> NSWindow? {
    NSApp.windows.first { String(describing: type(of: $0)).contains("AskBubblePanel") }
}
