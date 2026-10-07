//
//  Footnotes.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// GitHub's footnotes, which Apple's parser leaves as text: each `[^id]`
/// reference becomes a superscript number, in order of first use, and the
/// `[^id]: text` notes move to the end, numbered, under a rule. A reference
/// with no note (yet, mid-stream) and a note never referenced are left
/// alone and dropped respectively, as GitHub does. Code is never touched.
enum Footnotes {
    static func resolve(_ text: String) -> String {
        guard text.contains("[^") else { return text }

        // Notes out, outside code fences. An indented line continues a note.
        var fence = CodeFence()
        var lines: [(text: String, isCode: Bool)] = []
        var notes: [String: String] = [:]
        var noteID: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let wasOpen = fence.isOpen
            let isFence = fence.isFenceLine(line)
            if wasOpen || isFence {
                noteID = nil
                lines.append((line, true))
                continue
            }
            if let match = line.wholeMatch(of: #/\[\^([^\]\s]+)\]:[ \t]*(.*)/#) {
                let id = String(match.output.1)
                notes[id] = String(match.output.2)
                noteID = id
                continue
            }
            if let id = noteID, line.hasPrefix("  ") || line.hasPrefix("\t") {
                notes[id, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            noteID = nil
            lines.append((line, false))
        }
        // Mid-stream inside a code block: notes would land in the code.
        guard !notes.isEmpty, !fence.isOpen else { return text }

        // References to superscript numbers, skipping inline code.
        var order: [String] = []
        let body = lines.map { line -> String in
            guard !line.isCode else { return line.text }
            return line.text.replacing(#/`[^`\n]*`|\[\^([^\]\s]+)\]/#) { match in
                guard let id = match.output.1.map(String.init), notes[id] != nil else { return String(match.output.0) }
                if !order.contains(id) { order.append(id) }
                return "<sup>\(order.firstIndex(of: id)! + 1)</sup>"
            }
        }.joined(separator: "\n")
        guard !order.isEmpty else { return body }

        let list = order.enumerated().map { "\($0.offset + 1). \(notes[$0.element] ?? "")" }.joined(separator: "\n")
        return body.trimmingCharacters(in: .newlines) + "\n\n---\n\n" + list
    }
}
