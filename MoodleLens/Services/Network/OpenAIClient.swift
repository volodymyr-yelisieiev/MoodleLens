//
//  OpenAIClient.swift
//  MoodleLens
//
//  Created by Claude on 4/9/25.
//

import Foundation
import SwiftUI
// Import for centralized notification handling
import Cocoa

class OpenAIClient: OpenAIClientProtocol {
    // Singleton instance
    static let shared = OpenAIClient()

    // API endpoints
    private let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let visionCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")! // Same endpoint, different format

    // API key - should be provided by the user
    private var apiKey: String = ""

    // To track conversation context
    private var messages: [[String: String]] = []

    // Dependencies
    private var settingsManager: SettingsManagerProtocol
    private let notificationService: NotificationServiceProtocol
    private let codexClient: CodexCLIProviding

    // Flag to check if API key is set
    var hasApiKey: Bool {
        isConfigured()
    }

    private var usesCodexCLI: Bool {
        settingsManager.aiProvider == .codexCLI
    }

    // Initialize with dependencies
    init(
        settingsManager: SettingsManagerProtocol,
        notificationService: NotificationServiceProtocol,
        codexClient: CodexCLIProviding = CodexCLIClient()
    ) {
        self.settingsManager = settingsManager
        self.notificationService = notificationService
        self.codexClient = codexClient

        // Load API key from settings
        self.apiKey = settingsManager.apiKey

        // Add system message to start the conversation with user-defined context
        messages.append(["role": "system", "content": createSystemContext(questionType: "general")])
    }

    // Convenience initializer for singleton during transition to DI
    private convenience init() {
        // During transition, fallback to shared instances
        let settingsManager = DIContainer.shared.resolve(SettingsManagerProtocol.self) ?? SettingsManager.shared
        let notificationService = DIContainer.shared.resolve(NotificationServiceProtocol.self) ?? DefaultNotificationService()

        self.init(settingsManager: settingsManager, notificationService: notificationService)
    }

    // Helper method to create the system context message
    private func createSystemContext(questionType: String) -> String {
        // All request modes resolve to the shared instructions field.
        let contextPrompt: String
        switch questionType {
        case "screenshot":
            contextPrompt = settingsManager.screenshotContext
        case "text":
            contextPrompt = settingsManager.textContext
        default:
            contextPrompt = settingsManager.position
        }

        return contextPrompt
    }

    // Set or update the API key
    func setAPIKey(_ key: String) {
        self.apiKey = key
        // Also update in settings
        settingsManager.apiKey = key
    }

    // MARK: - Chat Completions API

    // Send a request to the OpenAI API with conversation context
    func sendMessage(_ message: String, questionType: String = "text", completion: @escaping (String?, Error?) -> Void) {
        if usesCodexCLI {
            sendCodexTextRequest(prompt: message, storedUserMessage: message, completion: completion)
            return
        }

        // Check if API key is set
        guard !apiKey.isEmpty else {
            let error = NSError(domain: "OpenAIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"])
            completion(nil, error)

            // Post error notification using NotificationManager
            notificationService.post(
                name: Notification.Name("OpenAIError"),
                object: ["error": "OpenAI API key is missing. Open Settings and paste a valid key."]
            )
            return
        }

        // Update system message with the user-defined context
        if messages.first?["role"] == "system" {
            let contextMessage = createSystemContext(questionType: questionType)
            messages[0] = ["role": "system", "content": contextMessage]
        }

        // Add user message to the conversation
        messages.append(["role": "user", "content": message])

        // Prepare request body
        let requestBody = sanitizeRequestBody(openAIRequestBody(messages: messages))

        // Convert request body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            let error = NSError(domain: "OpenAIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
            completion(nil, error)
            return
        }

        // Create request
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Send request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Handle network errors
            if let error = error {
                completion(nil, error)
                return
            }

            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                completion(nil, error)
                return
            }

            // Check status code
            guard (200...299).contains(httpResponse.statusCode) else {
                var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    errorMessage += " - \(responseBody)"
                }
                let error = NSError(domain: "OpenAIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(nil, error)
                return
            }

            // Parse response
            guard let data = data else {
                let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                completion(nil, error)
                return
            }

            do {
                // Parse JSON response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {

                    // Add assistant response to the conversation history
                    self.messages.append(["role": "assistant", "content": content])

                    // Return the response via callback only - let the caller post notifications
                    // to avoid duplicates
                    completion(content, nil)

                } else {
                    let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
                    completion(nil, error)

                    // Post error notification
                    self.notificationService.post(
                        name: Notification.Name("OpenAIError"),
                        object: ["error": "Failed to parse response from OpenAI."]
                    )
                }
            } catch {
                completion(nil, error)

                // Post error notification
                self.notificationService.post(
                    name: Notification.Name("OpenAIError"),
                    object: ["error": error.localizedDescription]
                )
            }
        }

        task.resume()
    }

    // Updated sendRequest method with notification posting
    func sendRequest(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendMessage(prompt) { [weak self] response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
            } else if let response = response {
                // Post notification about the response
                DispatchQueue.main.async {
                    // This notification will add the message to the conversation view
                    self.notificationService.post(
                        name: Notification.Name("OpenAIResponseReceived"),
                        object: ["response": response]
                    )
                }

                // Also call completion handler for callers that need the direct result
                // Async callers handle UI state directly.
                completion(.success(response))
            } else {
                completion(.failure(NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
            }
        }
    }

    // Send a request with context from replied messages
    func sendRequestWithContext(prompt: String, contextMessages: [Message], completion: @escaping (Result<String, Error>) -> Void) {
        if usesCodexCLI {
            let codexPrompt = buildCodexPrompt(prompt: prompt, contextMessages: contextMessages)
            sendCodexTextRequest(prompt: codexPrompt, storedUserMessage: prompt) { response, error in
                if let error {
                    completion(.failure(error))
                } else if let response {
                    completion(.success(response))
                } else {
                    completion(.failure(NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown Codex CLI response"])))
                }
            }
            return
        }

        // First check API key
        guard !apiKey.isEmpty else {
            let error = NSError(domain: "OpenAIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"])
            completion(.failure(error))

            // Post error notification
            notificationService.post(
                name: Notification.Name("OpenAIError"),
                object: ["error": "OpenAI API key is missing. Open Settings and paste a valid key."]
            )
            return
        }

        // Create a temporary message array for this request
        var tempMessages: [[String: String]] = []

        // Add system message (same as the one in our main messages array)
        if let systemMessage = messages.first(where: { $0["role"] == "system" }) {
            tempMessages.append(systemMessage)
        } else {
            // Add default system message if none exists
            tempMessages.append(["role": "system", "content": createSystemContext(questionType: "text")])
        }

        // Add context messages in sequence
        for contextMessage in contextMessages {
            let role = contextMessage.type == .user ? "user" : "assistant"

            // Combine all content parts into a single string
            let content = contextMessage.contents.map { content -> String in
                switch content.type {
                case .text:
                    return content.content
                case .code(let language):
                    return "```\(language)\n\(content.content)\n```"
                }
            }.joined(separator: "\n\n")

            tempMessages.append(["role": role, "content": content])
        }

        // Add the current prompt as a user message
        tempMessages.append(["role": "user", "content": prompt])

        // Prepare request body
        let requestBody = sanitizeRequestBody(openAIRequestBody(messages: tempMessages))

        // Convert request body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            let error = NSError(domain: "OpenAIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
            completion(.failure(error))
            return
        }

        // Create request
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Send request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Handle network errors
            if let error = error {
                completion(.failure(error))
                return
            }

            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                completion(.failure(error))
                return
            }

            // Check status code
            guard (200...299).contains(httpResponse.statusCode) else {
                var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    errorMessage += " - \(responseBody)"
                }
                let error = NSError(domain: "OpenAIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                completion(.failure(error))
                return
            }

            // Parse response
            guard let data = data else {
                let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                completion(.failure(error))
                return
            }

            do {
                // Parse JSON response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {

                    // Add the messages to our main conversation history
                    // First the user prompt (which was already added in the UI)
                    self.messages.append(["role": "user", "content": prompt])

                    // Then the assistant response
                    self.messages.append(["role": "assistant", "content": content])

                    // Post notification about the response
                    DispatchQueue.main.async {
                        self.notificationService.post(
                            name: Notification.Name("OpenAIResponseReceived"),
                            object: ["response": content]
                        )
                    }

                    // Return the result
                    completion(.success(content))
                } else {
                    let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
                    completion(.failure(error))

                    // Post error notification
                    self.notificationService.post(
                        name: Notification.Name("OpenAIError"),
                        object: ["error": "Failed to parse response from OpenAI."]
                    )
                }
            } catch {
                completion(.failure(error))

                // Post error notification
                self.notificationService.post(
                    name: Notification.Name("OpenAIError"),
                    object: ["error": error.localizedDescription]
                )
            }
        }

        task.resume()
    }

    // Clear conversation history (except for the system message)
    func clearConversation() {
        messages = messages.filter { $0["role"] == "system" }
    }

    // Function to check if API key is configured
    func isConfigured() -> Bool {
        usesCodexCLI ? codexClient.isReady : !apiKey.isEmpty
    }

    // MARK: - Vision API (Image Processing)

    /// Send an image to OpenAI for processing using the Vision API
    /// - Parameters:
    ///   - imageURL: URL of the image file
    ///   - prompt: Text prompt to guide image analysis
    ///   - contextInfo: Optional context information for replied messages
    ///   - completion: Callback with result
    func sendImageRequest(imageURL: URL, prompt: String, contextInfo: [String: Any]? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let isAskRequest = contextInfo?["source"] as? String == AskController.source

        if usesCodexCLI {
            sendCodexImageRequest(imageURL: imageURL, prompt: prompt, contextInfo: contextInfo, completion: completion)
            return
        }

        // Check if API key is set
        guard !apiKey.isEmpty else {
            let error = NSError(domain: "OpenAIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not set"])
            completion(.failure(error))

            if !isAskRequest {
                notificationService.post(
                    name: Notification.Name("OpenAIError"),
                    object: ["error": "OpenAI API key is missing. Open Settings and paste a valid key."]
                )
            }
            return
        }

        // Verify the file exists
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            let error = NSError(domain: "OpenAIClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "Image file not found"])
            completion(.failure(error))
            return
        }

        do {
            // Read image data
            let imageData = try Data(contentsOf: imageURL)
            // Convert image data to base64
            let base64Image = imageData.base64EncodedString()

            // Create local messages array for this request
            var requestMessages: [[String: Any]] = []

            // Use the screenshot context from settings
            requestMessages.append([
                "role": "system",
                "content": settingsManager.screenshotContext
            ])

            // Add context messages if available
            if let contextInfo = contextInfo,
               let replyChain = contextInfo["replyChain"] as? [UUID],
               !replyChain.isEmpty {

                // Find the referenced messages
                for messageId in replyChain {
                    // We need to search in our main messages array
                    if let messageIndex = self.messages.firstIndex(where: {
                        if let jsonId = $0["id"],
                           let uuid = UUID(uuidString: jsonId) {
                            return uuid == messageId
                        }
                        return false
                    }) {
                        // Add this message to the context
                        requestMessages.append(self.messages[messageIndex])
                    }
                }
            }

            // Create the message content with text and image
            var messageContent: [[String: Any]] = []

            // Add text part
            messageContent.append([
                "type": "text",
                "text": prompt
            ])

            // Add image part
            messageContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/png;base64,\(base64Image)"
                ]
            ])

            // Create the image message
            let userMessage: [String: Any] = [
                "role": "user",
                "content": messageContent
            ]

            // Add the user message to our request messages
            requestMessages.append(userMessage)

            // Prepare request body
            var requestBody = sanitizeRequestBody(openAIRequestBody(messages: requestMessages))
            requestBody["max_completion_tokens"] = 1000

            // Convert request body to JSON data
            guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
                let error = NSError(domain: "OpenAIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
                completion(.failure(error))
                return
            }

            // Create request
            var request = URLRequest(url: visionCompletionsURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            // Send request
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                // Handle network errors
                if let error = error {
                    completion(.failure(error))
                    return
                }

                // Check HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    completion(.failure(error))
                    return
                }

                // Check status code
                guard (200...299).contains(httpResponse.statusCode) else {
                    var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                        errorMessage += " - \(responseBody)"
                    }
                    let error = NSError(domain: "OpenAIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    completion(.failure(error))
                    return
                }

                // Parse response
                guard let data = data else {
                    let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                    completion(.failure(error))
                    return
                }

                do {
                    // Parse JSON response
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {

                        if !isAskRequest {
                            self.messages.append(["role": "user", "content": "Screenshot analysis request: \(prompt)"])
                            self.messages.append(["role": "assistant", "content": content])
                        }

                        if !isAskRequest {
                            DispatchQueue.main.async {
                                var notificationObject: [String: Any] = ["response": content]
                                if let contextInfo {
                                    notificationObject["contextInfo"] = contextInfo
                                    if let tabID = contextInfo["tabID"] {
                                        notificationObject["tabID"] = tabID
                                    }
                                }
                                self.notificationService.post(
                                    name: Notification.Name("OpenAIResponseReceived"),
                                    object: notificationObject
                                )
                            }
                        }

                        // Return the result
                        completion(.success(content))
                    } else {
                        let error = NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse vision response"])
                        completion(.failure(error))

                        if !isAskRequest {
                            self.notificationService.post(
                                name: Notification.Name("OpenAIError"),
                                object: ["error": "Failed to parse vision response from OpenAI."]
                            )
                        }
                    }
                } catch {
                    completion(.failure(error))

                    if !isAskRequest {
                        self.notificationService.post(
                            name: Notification.Name("OpenAIError"),
                            object: ["error": error.localizedDescription]
                        )
                    }
                }
            }

            task.resume()
        } catch {
            completion(.failure(error))

            if !isAskRequest {
                notificationService.post(
                    name: Notification.Name("OpenAIError"),
                    object: ["error": "Error reading image file: \(error.localizedDescription)"]
                )
            }
        }
    }

    // MARK: - Async API Methods (Modern Implementation)

    func sendRequest(prompt: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Use sendMessage directly to avoid notification posting
            sendMessage(prompt) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }

    func sendRequestWithContext(prompt: String, contextMessages: [Message]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Handle the callback result directly to avoid duplicate notifications.
            sendRequestWithContext(prompt: prompt, contextMessages: contextMessages) { result in
                continuation.resume(with: result)
            }
        }
    }

    func sendImageRequest(imageURL: URL, prompt: String, contextInfo: [String: Any]?) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            sendImageRequest(imageURL: imageURL, prompt: prompt, contextInfo: contextInfo) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func sendCodexTextRequest(prompt: String, storedUserMessage: String, completion: @escaping (String?, Error?) -> Void) {
        codexClient.sendTextRequest(prompt: prompt) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let response):
                self.messages.append(["role": "user", "content": storedUserMessage])
                self.messages.append(["role": "assistant", "content": response])
                completion(response, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    private func openAIRequestBody(messages: Any) -> [String: Any] {
        OpenAIRequestBuilder.requestBody(
            model: settingsManager.openAIModel,
            messages: messages,
            reasoningEffort: settingsManager.openAIReasoningEffort,
            serviceTier: settingsManager.openAISpeed
        )
    }

    private func sanitizeRequestBody(_ requestBody: [String: Any]) -> [String: Any] {
        var sanitized = requestBody
        let deprecatedMaxTokens = sanitized.removeValue(forKey: "max_tokens")
        if sanitized["max_completion_tokens"] == nil {
            if let maxTokens = deprecatedMaxTokens as? Int {
                sanitized["max_completion_tokens"] = maxTokens
            } else if let maxTokens = deprecatedMaxTokens as? Double {
                sanitized["max_completion_tokens"] = Int(maxTokens)
            } else if let maxTokens = deprecatedMaxTokens as? String, let parsedValue = Int(maxTokens) {
                sanitized["max_completion_tokens"] = parsedValue
            }
        }
        return sanitized
    }

    private func sendCodexImageRequest(imageURL: URL, prompt: String, contextInfo: [String: Any]?, completion: @escaping (Result<String, Error>) -> Void) {
        let isAskRequest = contextInfo?["source"] as? String == AskController.source
        codexClient.sendImageRequest(imageURL: imageURL, prompt: prompt) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let response):
                if !isAskRequest {
                    self.messages.append(["role": "user", "content": "Screenshot analysis request: \(prompt)"])
                    self.messages.append(["role": "assistant", "content": response])
                    var notificationObject: [String: Any] = ["response": response]
                    if let contextInfo {
                        notificationObject["contextInfo"] = contextInfo
                        if let tabID = contextInfo["tabID"] {
                            notificationObject["tabID"] = tabID
                        }
                    }
                    self.notificationService.post(
                        name: Notification.Name("OpenAIResponseReceived"),
                        object: notificationObject
                    )
                }
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func buildCodexPrompt(prompt: String, contextMessages: [Message]) -> String {
        guard !contextMessages.isEmpty else { return prompt }

        let context = contextMessages.map { message -> String in
            let role = message.type == .user ? "User" : "Assistant"
            let content = message.contents.map { content -> String in
                switch content.type {
                case .text:
                    return content.content
                case .code(let language):
                    return "```\(language)\n\(content.content)\n```"
                }
            }.joined(separator: "\n\n")

            return "\(role):\n\(content)"
        }.joined(separator: "\n\n")

        return "Use this prior conversation as context:\n\n\(context)\n\nUser:\n\(prompt)"
    }
}
