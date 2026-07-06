//
//  AIServiceError.swift
//  MoodleLens
//
//  Created on 5/23/25.
//

import Foundation

/// Structured error types for AI services
enum AIServiceError: LocalizedError {
    case apiKeyMissing
    case apiKeyInvalid
    case networkTimeout
    case networkConnectionLost
    case invalidResponse
    case responseParsingFailed
    case fileNotFound(String)
    case fileTooSmall(String)
    case invalidFileFormat(String)
    case requestCancelled
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String?)
    case quotaExceeded
    case imageTooLarge
    case imageProcessingFailed
    case permissionDenied(permission: String)
    case providerConfigurationInvalid
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "OpenAI API key is missing. Open Settings and paste a valid key."
        case .apiKeyInvalid:
            return "Invalid OpenAI API key. Please check your settings."
        case .networkTimeout:
            return "Request timed out. Please check your internet connection and try again."
        case .networkConnectionLost:
            return "Network connection lost. Please check your internet connection."
        case .invalidResponse:
            return "Received invalid response from server."
        case .responseParsingFailed:
            return "Failed to parse server response."
        case .fileNotFound(let filename):
            return "File not found: \(filename)"
        case .fileTooSmall(let filename):
            return "File too small or empty: \(filename). Please ensure the file contains valid data."
        case .invalidFileFormat(let format):
            return "Invalid or unsupported file format: \(format)"
        case .requestCancelled:
            return "Request was cancelled."
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Please wait \(Int(retryAfter)) seconds before trying again."
            } else {
                return "Rate limit exceeded. Please try again later."
            }
        case .serverError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            } else {
                return "Server error (\(statusCode))"
            }
        case .quotaExceeded:
            return "API quota exceeded. Please check your OpenAI account billing."
        case .imageTooLarge:
            return "Image is too large to process. Capture a smaller area or try again with a lower-resolution screenshot."
        case .imageProcessingFailed:
            return "Failed to process image. Please try with a different image."
        case .permissionDenied(let permission):
            return "\(permission) permission is required. Enable it in System Settings → Privacy & Security, then try again."
        case .providerConfigurationInvalid:
            return "OpenAI rejected the selected model, reasoning, or speed setting. Open Settings, refresh models, and choose a supported provider configuration."
        case .unknown(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .apiKeyMissing, .apiKeyInvalid:
            return "Open settings and configure a valid OpenAI API key."
        case .networkTimeout, .networkConnectionLost:
            return "Check your internet connection and try again."
        case .rateLimitExceeded:
            return "Wait a moment before making another request."
        case .quotaExceeded:
            return "Check your OpenAI account billing and usage limits."
        case .imageTooLarge:
            return "Capture a smaller area or reduce the image resolution before trying again."
        case .permissionDenied:
            return "Open System Settings → Privacy & Security to grant required permissions."
        case .providerConfigurationInvalid:
            return "Open Settings, refresh the model list, and choose a supported model/reasoning/speed combination."
        default:
            return "Try again. If the problem persists, restart the app."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkTimeout, .networkConnectionLost:
            return true
        case .serverError(let code, _):
            return code >= 500 || code == 408 || code == 429
        case .rateLimitExceeded:
            return true
        default:
            return false
        }
    }
}

/// Extension to convert common errors to AIServiceError
extension AIServiceError {
    static func from(_ error: Error) -> AIServiceError {
        if let aiError = error as? AIServiceError {
            return aiError
        }
        
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorTimedOut:
            return .networkTimeout
        case NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
            return .networkConnectionLost
        case NSURLErrorCancelled:
            return .requestCancelled
        case 401:
            return .apiKeyInvalid
        case 429:
            let retryAfter = nsError.userInfo["Retry-After"] as? TimeInterval
            return .rateLimitExceeded(retryAfter: retryAfter)
        case 402, 403:
            return .quotaExceeded
        case 400, 422:
            if isProviderConfigurationError(nsError.localizedDescription) {
                return .providerConfigurationInvalid
            }
            return .invalidResponse
        case 404:
            if isProviderConfigurationError(nsError.localizedDescription) {
                return .providerConfigurationInvalid
            }
            return .fileNotFound(nsError.localizedDescription)
        case 500...599:
            return .serverError(statusCode: nsError.code, message: nsError.localizedDescription)
        default:
            return .unknown(error)
        }
    }

    private static func isProviderConfigurationError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return [
            "model",
            "reasoning",
            "service_tier",
            "service tier",
            "speed",
            "unsupported parameter",
            "unsupported value"
        ].contains { lowercased.contains($0) }
    }
}
