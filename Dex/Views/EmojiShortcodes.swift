//
//  EmojiShortcodes.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// GitHub's emoji shortcodes (`:tada:`, `:+1:`) as emoji. Strict, so
/// ordinary text never changes: only GitHub's own names, lowercase, never
/// inside code, and never touching a letter, digit, colon, slash, underscore
/// or "@" on either side, so times (`10:30:45`), scopes (`std::vector`),
/// ratios and URLs stay as written.
enum EmojiShortcodes {
    static let table: [String: String] = {
        var table: [String: String] = [:]
        for line in source.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { table[String(parts[0])] = String(parts[1]) }
        }
        return table
    }()

    static func replace(_ text: String) -> String {
        guard text.contains(":") else { return text }
        var fence = CodeFence()
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let wasOpen = fence.isOpen
            let isFence = fence.isFenceLine(line)
            guard !wasOpen, !isFence, line.contains(":") else { return String(line) }
            return replaceInLine(line)
        }.joined(separator: "\n")
    }

    private static func replaceInLine(_ line: Substring) -> String {
        var result = ""
        var rest = line
        while let match = rest.firstMatch(of: #/`[^`\n]*`|:([a-z0-9_+\-]+):/#) {
            result += rest[..<match.range.lowerBound]
            let whole = rest[match.range]
            if let name = match.output.1, let emoji = table[String(name)],
               !touches(before: match.range.lowerBound, after: match.range.upperBound, in: line) {
                result += emoji
            } else if whole.hasPrefix(":") {
                // Not a shortcode: keep the first colon and look again from
                // the second, which may open the next one (":x::tada:").
                result += ":"
                rest = rest[rest.index(after: match.range.lowerBound)...]
                continue
            } else {
                result += whole
            }
            rest = rest[match.range.upperBound...]
        }
        return result + rest
    }

    private static func touches(before start: Substring.Index, after end: Substring.Index, in line: Substring) -> Bool {
        // A slash, underscore or "@" joins too: paths and URLs ("/a/:b:") stay whole.
        func joins(_ character: Character) -> Bool { character.isLetter || character.isNumber || ":/_@".contains(character) }
        if start > line.startIndex, joins(line[line.index(before: start)]) { return true }
        if end < line.endIndex, joins(line[end]) { return true }
        return false
    }
}
