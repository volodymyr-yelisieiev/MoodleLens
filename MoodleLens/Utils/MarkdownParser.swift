//
//  MarkdownParser.swift
//  MoodleLens
//

import Foundation

struct MarkdownParser {
    static func parse(text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
