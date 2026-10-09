//
//  ChatTitle.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// A saved chat's name: the first message, cut short, until the server
/// names it after its first reply.
enum ChatTitle {
    /// The longest a fallback title runs before it is cut at a word.
    static let fallbackLength = 40
    /// The most words a model-made title keeps.
    static let maxWords = 4

    /// Lowercase inside a title unless they come first.
    static let smallWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet",
        "as", "at", "by", "in", "of", "on", "per", "to", "up", "via", "vs",
    ]

    /// The first line of `text`, cut at a word to fit `fallbackLength`.
    static func fallback(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let words = line.split(whereSeparator: \.isWhitespace)
        var title = ""
        for word in words {
            let next = title.isEmpty ? String(word) : "\(title) \(word)"
            guard next.count <= fallbackLength else {
                // A first word too long to fit is cut mid-word.
                if title.isEmpty { title = String(word.prefix(fallbackLength)) }
                return "\(title)…"
            }
            title = next
        }
        return title
    }

    /// The server's name cut to `maxWords` and put in Title Case; nil when
    /// nothing usable is left.
    static func clean(_ raw: String) -> String? {
        var text = raw
        // A model that thinks aloud in its answer anyway.
        if let end = text.range(of: "</think>") {
            text = String(text[end.upperBound...])
        }
        // Quotes, markdown and punctuation around words go; C++ and C# keep theirs.
        let edges = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+#")).inverted
        var line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: edges) }
            .first { !$0.isEmpty } ?? ""
        for label in ["title:", "name:"] where line.lowercased().hasPrefix(label) {
            line = String(line.dropFirst(label.count))
        }
        let words = line.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: edges) }
            // A heading's # marks are no word.
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .prefix(maxWords)
        guard !words.isEmpty else { return nil }
        return words.enumerated()
            .map { titleCase($0.element, isFirst: $0.offset == 0) }
            .joined(separator: " ")
    }

    /// Capitalizes the first letter; a word with capitals past its first
    /// letter (iOS, SwiftUI, API) is left as it is.
    static func titleCase(_ word: String, isFirst: Bool) -> String {
        if word.dropFirst().contains(where: \.isUppercase) { return word }
        let lower = word.lowercased()
        if !isFirst && smallWords.contains(lower) { return lower }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
