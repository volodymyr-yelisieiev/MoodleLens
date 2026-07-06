//
//  CodexCLIClient.swift
//  MoodleLens
//

import Foundation

enum CodexCLIError: LocalizedError {
    case missingCLI
    case notAuthenticated
    case commandFailed(status: Int32, details: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingCLI:
            return "Codex CLI is not installed. Install Codex, make sure `codex` is on PATH, then run `codex login` or `codex login --device-auth`."
        case .notAuthenticated:
            return "Codex CLI is not authenticated. Run `codex login` or `codex login --device-auth` in Terminal, then try again."
        case .commandFailed(let status, let details):
            let lowercasedDetails = details.lowercased()
            if lowercasedDetails.contains("model_reasoning_effort") ||
                lowercasedDetails.contains("reasoning effort") ||
                lowercasedDetails.contains("strict config") {
                return "Codex CLI does not support reasoning \(SettingsManager.shared.codexReasoningEffort). Update Codex, change reasoning in Settings, or switch to the OpenAI API provider."
            }
            if lowercasedDetails.contains("service_tier") ||
                lowercasedDetails.contains("tier") {
                return "Codex CLI did not accept the selected provider tier. Set tier to the default value and try again."
            }
            if lowercasedDetails.contains("gpt-5.5") ||
                (lowercasedDetails.contains("model") && lowercasedDetails.contains("unsupported")) {
                return "Codex CLI could not use model \(SettingsManager.shared.codexModel). Update Codex, change model in Settings, or switch to the OpenAI API provider."
            }
            if details.isEmpty {
                return "Codex CLI failed with exit code \(status). If you are not logged in, run `codex login` or `codex login --device-auth`."
            }
            return "Codex CLI failed with exit code \(status): \(details)"
        case .emptyOutput:
            return "Codex CLI returned an empty response. Try again, or run `codex login` if the CLI is not authenticated."
        }
    }
}

struct CodexCLIStatus: Equatable {
    let executablePath: String?
    let isLoggedIn: Bool?
    let message: String

    var isInstalled: Bool {
        executablePath != nil
    }

    var isReady: Bool {
        isInstalled && isLoggedIn == true
    }
}

enum CodexModelCatalog {
    private struct Catalog: Decodable {
        let models: [Model]
    }

    private struct Model: Decodable {
        let slug: String
        let visibility: String?
    }

    static func fetchModelIDs() throws -> [String] {
        guard let executableURL = CodexCLIClient.findExecutable() else {
            throw CodexCLIError.missingCLI
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["debug", "models"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CodexCLIError.commandFailed(status: process.terminationStatus, details: stderrText)
        }
        return try parseModelIDs(from: data)
    }

    static func parseModelIDs(from data: Data) throws -> [String] {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        return cleanedModelIDs(catalog.models.compactMap { model in
            guard model.visibility != "hide" else { return nil }
            return model.slug
        })
    }

    static func fallbackModelIDs(selected: String) -> [String] {
        mergedModelIDs(AIModelDefaults.codexModelValues, selected: selected)
    }

    static func mergedModelIDs(_ modelIDs: [String], selected: String) -> [String] {
        var values = cleanedModelIDs(modelIDs)
        let selected = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty && !values.contains(selected) {
            values.insert(selected, at: 0)
        }
        return values
    }

    private static func cleanedModelIDs(_ modelIDs: [String]) -> [String] {
        var seen = Set<String>()
        return modelIDs.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { return nil }
            seen.insert(value)
            return value
        }
    }
}

protocol CodexCLIProviding {
    var isReady: Bool { get }
    func sendTextRequest(prompt: String, completion: @escaping (Result<String, Error>) -> Void)
    func sendImageRequest(imageURL: URL, prompt: String, completion: @escaping (Result<String, Error>) -> Void)
}

final class CodexCLIClient: CodexCLIProviding {
    private let executableURL: URL?

    init(executableURL: URL? = CodexCLIClient.findExecutable()) {
        self.executableURL = executableURL
    }

    var isInstalled: Bool {
        executableURL != nil
    }

    var isReady: Bool {
        status.isReady
    }

    var status: CodexCLIStatus {
        Self.currentStatus(executableURL: executableURL)
    }

    func sendTextRequest(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        run(prompt: prompt, imageURL: nil, completion: completion)
    }

    func sendImageRequest(imageURL: URL, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        run(prompt: prompt, imageURL: imageURL, completion: completion)
    }

    private func run(prompt: String, imageURL: URL?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let executableURL else {
            completion(.failure(CodexCLIError.missingCLI))
            return
        }

        if let imageURL, !FileManager.default.fileExists(atPath: imageURL.path) {
            completion(.failure(AIServiceError.fileNotFound(imageURL.lastPathComponent)))
            return
        }

        let outputURL = TempFileManager.shared.createTempFileURL(prefix: "CodexOutput", extension: "txt")
        let process = Process()
        process.executableURL = executableURL
        process.arguments = Self.buildArguments(prompt: prompt, imageURL: imageURL, outputURL: outputURL)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let outputQueue = DispatchQueue(label: "io.github.volodymyryelisieiev.moodlelens.codex-output")
        var stdoutData = Data()
        var stderrData = Data()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.async {
                stdoutData.append(data)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.async {
                stderrData.append(data)
            }
        }

        process.terminationHandler = { process in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            outputQueue.async {
                let stdoutText = String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let finalText = (try? String(contentsOf: outputURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                DispatchQueue.main.async {
                    TempFileManager.shared.deleteTempFile(outputURL)

                    if process.terminationStatus == 0 {
                        let responseText = finalText.isEmpty ? stdoutText : finalText
                        if responseText.isEmpty {
                            completion(.failure(CodexCLIError.emptyOutput))
                        } else {
                            completion(.success(responseText))
                        }
                        return
                    }

                    if Self.looksLikeAuthenticationFailure(stdoutText) || Self.looksLikeAuthenticationFailure(stderrText) {
                        completion(.failure(CodexCLIError.notAuthenticated))
                        return
                    }

                    completion(.failure(CodexCLIError.commandFailed(
                        status: process.terminationStatus,
                        details: Self.firstUsefulDiagnostic(stdout: stdoutText, stderr: stderrText)
                    )))
                }
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            TempFileManager.shared.deleteTempFile(outputURL)
            completion(.failure(error))
        }
    }

    static func buildArguments(
        prompt: String,
        imageURL: URL?,
        outputURL: URL,
        model: String = SettingsManager.shared.codexModel,
        reasoningEffort: String = SettingsManager.shared.codexReasoningEffort,
        speed: String = SettingsManager.shared.codexSpeed
    ) -> [String] {
        var args = [
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--strict-config",
            "--model",
            model,
            "-c",
            "model_reasoning_effort=\"\(reasoningEffort)\"",
            "--sandbox",
            "read-only",
            "--skip-git-repo-check",
            "--color",
            "never",
            "--output-last-message",
            outputURL.path
        ]

        if let imageURL {
            args.append(contentsOf: ["-i", imageURL.path])
        }

        args.append("--")
        args.append(prompt)
        return args
    }

    static func findExecutable() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    static func currentStatus(executableURL: URL? = CodexCLIClient.findExecutable()) -> CodexCLIStatus {
        guard let executableURL else {
            return CodexCLIStatus(
                executablePath: nil,
                isLoggedIn: nil,
                message: "Codex CLI was not found. Install Codex, then run codex login or codex login --device-auth."
            )
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["login", "status"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = [stdoutText, stderrText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            return CodexCLIStatus(
                executablePath: executableURL.path,
                isLoggedIn: process.terminationStatus == 0,
                message: message.isEmpty ? "Codex CLI status check completed." : message
            )
        } catch {
            return CodexCLIStatus(
                executablePath: executableURL.path,
                isLoggedIn: false,
                message: "Could not run codex login status: \(error.localizedDescription)"
            )
        }
    }

    private static func looksLikeAuthenticationFailure(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("not authenticated") ||
            lowercased.contains("not logged in") ||
            lowercased.contains("login") ||
            lowercased.contains("401") ||
            lowercased.contains("unauthorized") ||
            lowercased.contains("oauth")
    }

    private static func firstUsefulDiagnostic(stdout: String, stderr: String) -> String {
        let combined = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return combined
            .split(separator: "\n")
            .prefix(3)
            .joined(separator: " ")
    }
}
