//
//  OpenAIModelCatalog.swift
//  MoodleLens
//

import Foundation

enum AIModelCapability {
    static func supportsReasoning(model: String) -> Bool {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("o") || value.hasPrefix("gpt-5") || value.contains("codex")
    }
}

enum OpenAIModelCatalogError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid models response."
        case .httpStatus(let status):
            return "OpenAI models request failed with HTTP \(status)."
        }
    }
}

enum OpenAIModelCatalog {
    private struct ModelListResponse: Decodable {
        let data: [Model]
    }

    private struct Model: Decodable {
        let id: String
    }

    static let endpoint = URL(string: "https://api.openai.com/v1/models")!

    static func fetchModelIDs(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIModelCatalogError.httpStatus(httpResponse.statusCode)
        }
        return try parseModelIDs(from: data)
    }

    static func parseModelIDs(from data: Data) throws -> [String] {
        let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return cleanedModelIDs(response.data.map(\.id))
    }

    static func fallbackModelIDs(selected: String) -> [String] {
        mergedModelIDs([AIModelDefaults.openAIModel], selected: selected)
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
        let blockedFragments = ["embedding", "whisper", "tts", "dall-e", "image", "audio", "realtime", "transcribe"]
        let likelyTextPrefixes = ["gpt-", "o", "chatgpt-", "codex-"]
        let values = modelIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { model in
                let lowercased = model.lowercased()
                return likelyTextPrefixes.contains { lowercased.hasPrefix($0) }
                    && !blockedFragments.contains { lowercased.contains($0) }
            }
        return Array(Set(values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}

enum OpenAIRequestBuilder {
    static func requestBody(
        model: String,
        messages: Any,
        reasoningEffort: String,
        serviceTier: String
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages
        ]
        if AIModelCapability.supportsReasoning(model: model) {
            body["reasoning_effort"] = reasoningEffort
        }
        if serviceTier != AIModelDefaults.openAISpeed {
            body["service_tier"] = serviceTier
        }
        return body
    }
}
