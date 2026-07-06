//
//  MessageModels.swift
//  MoodleLens
//
//  Created on 4/20/25.
//

import Foundation
import SwiftUI

/// Represents the content of a single part of a message (text or code)
struct MessageContent: Equatable, Identifiable {
    let id = UUID()
    
    enum ContentType: Equatable {
        case text
        case code(language: String)
    }
    
    let content: String
    let type: ContentType
    
    static func == (lhs: MessageContent, rhs: MessageContent) -> Bool {
        return lhs.content == rhs.content && lhs.type == rhs.type
    }
}

/// Represents a single message in the conversation
struct Message: Identifiable, Equatable {
    enum MessageType: Equatable {
        case user
        case assistant
    }
    
    let id = UUID()
    let contents: [MessageContent]
    let type: MessageType
    let timestamp: Date
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
               lhs.contents == rhs.contents &&
               lhs.type == rhs.type &&
               lhs.timestamp == rhs.timestamp
    }
    
    /// Convenience initializer for simple text messages
    init(text: String, type: MessageType, timestamp: Date = Date()) {
        self.contents = Message.parseTextForCodeBlocks(text)
        self.type = type
        self.timestamp = timestamp
    }
    
    /// Parses a text string to extract code blocks and regular text
    static func parseTextForCodeBlocks(_ text: String) -> [MessageContent] {
        var contents: [MessageContent] = []
        let nonBreakingWhitespace = CharacterSet.whitespacesAndNewlines

        func trimBlockBoundary(_ value: String, isLeading: Bool) -> String {
            var trimmed = value
            if isLeading {
                trimmed = trimmed.replacingOccurrences(
                    of: #"^[ \t]*\r?\n+[ \t]*"#,
                    with: "",
                    options: .regularExpression
                )
                return trimmed
            }
            trimmed = trimmed.replacingOccurrences(
                of: #"[ \t]*\r?\n+[ \t]*$"#,
                with: "",
                options: .regularExpression
            )
            return trimmed
        }

        // Pattern to find code blocks with ```language\ncode\n``` syntax
        let codeBlockPattern = try? NSRegularExpression(
            pattern: "```([a-zA-Z0-9]*)?\\s*\\n?([\\s\\S]*?)\\n?```",
            options: []
        )
        
        let nsText = text as NSString
        var lastIndex = 0
        
        // Find all code blocks
        if let matches = codeBlockPattern?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
            for match in matches {
                // Add text before code block
                let textBeforeRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                if textBeforeRange.length > 0 {
                    let rawTextBefore = nsText.substring(with: textBeforeRange)
                    let textBefore = trimBlockBoundary(rawTextBefore, isLeading: false)
                    if !textBefore.isEmpty {
                        contents.append(MessageContent(content: textBefore, type: .text))
                    }
                }
                
                // Extract language if specified
                let languageRange = match.range(at: 1)
                let language: String
                if languageRange.location != NSNotFound && languageRange.length > 0 {
                    language = nsText.substring(with: languageRange).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    language = "text" // Default language if not specified
                }
                
                // Extract code
                let codeRange = match.range(at: 2)
                if codeRange.location != NSNotFound {
                    let code = nsText.substring(with: codeRange)
                    let trimmedCode = code.trimmingCharacters(in: nonBreakingWhitespace)
                    if !trimmedCode.isEmpty {
                        contents.append(MessageContent(content: trimmedCode, type: .code(language: language)))
                    }
                }
                
                lastIndex = match.range.location + match.range.length
            }
        }
        
        // Add any remaining text after the last code block
        if lastIndex < nsText.length {
            let rawTextAfter = nsText.substring(with: NSRange(location: lastIndex, length: nsText.length - lastIndex))
            let textAfter = trimBlockBoundary(rawTextAfter, isLeading: true)
            
            if !textAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contents.append(MessageContent(content: textAfter, type: .text))
            }
        }
        
        // If no content was parsed, just use the original text
        if contents.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contents.append(MessageContent(content: text.trimmingCharacters(in: .newlines), type: .text))
        }
        
        return contents
    }
}
