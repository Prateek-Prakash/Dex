//
//  HTMLBlock.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// Block-level HTML in a reply (a chunk that starts a line with `<div>`,
/// `<table>`, `<h2>` and the like), rewritten as Markdown so it draws with
/// the rest of the reply. Apple's parser hands such a chunk over as one raw
/// run with no block of its own, which otherwise drew nothing at all.
///
/// Covers p/div, h1–h6, ul/ol/li, table/tr/th/td, blockquote, pre, hr and
/// details/summary (shown open). Inline tags are left in place for
/// `InlineHTML`, except `<code>`, which becomes backticks. Tags whose content
/// isn't reading text (`<script>`, `<style>`, `<iframe>`…) go with their
/// content, as GitHub filters them. Any other tag is dropped and its text kept. Markdown code fences inside the chunk (a
/// ```` ``` ```` block in `<details>`) pass through untouched. Tolerant of a
/// chunk cut off mid-stream.
enum HTMLBlock {
    static func markdown(from html: String) -> String {
        var converter = Converter()
        var fence = CodeFence()
        var markup = ""
        var code = ""
        for line in html.split(separator: "\n", omittingEmptySubsequences: false) {
            let wasOpen = fence.isOpen
            let isFence = fence.isFenceLine(line)
            if wasOpen || isFence {
                if !wasOpen {
                    tokens(markup).forEach { converter.take($0) }
                    markup = ""
                }
                code += line + "\n"
                if wasOpen && isFence {
                    converter.code(code)
                    code = ""
                }
            } else {
                markup += line + "\n"
            }
        }
        // A fence still open mid-stream.
        if !code.isEmpty { converter.code(code) }
        tokens(markup).forEach { converter.take($0) }
        return converter.finish()
    }

    // MARK: Tokens

    enum Token: Equatable {
        case open(String, attributes: String)
        case close(String)
        case text(String)
    }

    static func tokens(_ html: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(html)
        while let match = rest.firstMatch(of: #/<!--[\s\S]*?-->|<(/?)([A-Za-z][A-Za-z0-9]*)([^<>]*)>/#) {
            if match.range.lowerBound > rest.startIndex {
                tokens.append(.text(String(rest[..<match.range.lowerBound])))
            }
            if let name = match.output.2 {
                if isTagName(name) {
                    let name = name.lowercased()
                    tokens.append(match.output.1?.isEmpty == false ? .close(name) : .open(name, attributes: String(match.output.3 ?? "")))
                } else {
                    tokens.append(.text(String(rest[match.range])))
                }
            }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { tokens.append(.text(String(rest))) }
        return tokens
    }

    // MARK: Conversion

    /// Tags left for `InlineHTML` to style.
    static let inlineTags: Set<String> = [
        "u", "ins", "s", "del", "strike", "b", "strong", "i", "em",
        "sup", "sub", "mark", "kbd", "a", "br",
    ]

    private struct Converter {
        /// Text being written; quotes and table cells get their own until they close.
        private var buffers: [String] = [""]
        private var lists: [(ordered: Bool, count: Int)] = []
        private var tables: [Table] = []
        private var quoteDepths: [Int] = []
        private var preDepth = 0
        private var preLanguage: String?
        /// Inside tags whose content is dropped.
        private var skipDepth = 0
        /// Inside `<code>`, written as a code span.
        private var codeDepth = 0
        static let skipped: Set<String> = ["script", "style", "noscript", "template", "title", "textarea", "iframe", "head", "object"]

        struct Table {
            var rows: [[String]] = []
            var headerRows = 0
            var isHeaderRow = false
        }

        mutating func take(_ token: Token) {
            if case .open(let name, let attributes) = token, Self.skipped.contains(name) {
                // `<iframe … />` closes itself: nothing inside to skip.
                if !attributes.trimmingCharacters(in: .whitespaces).hasSuffix("/") { skipDepth += 1 }
                return
            }
            if case .close(let name) = token, Self.skipped.contains(name) {
                skipDepth = max(0, skipDepth - 1)
                return
            }
            guard skipDepth == 0 else { return }
            switch token {
            case .text(let text):
                write(preDepth > 0 ? HTMLBlock.decoded(text) : flowing(text))
            case .open(let name, let attributes):
                open(name, attributes: attributes)
            case .close(let name):
                close(name)
            }
        }

        /// A Markdown code fence, written as is on its own lines.
        mutating func code(_ fenced: String) {
            write("\n\n" + fenced + "\n")
        }

        mutating func finish() -> String {
            // Close whatever a cut-off chunk left open, innermost first.
            if preDepth > 0 { close("pre") }
            while !tables.isEmpty { close("table") }
            while !quoteDepths.isEmpty { close("blockquote") }
            var text = buffers.joined()
            while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var inCell: Bool { buffers.count > 1 + quoteDepths.count }

        private mutating func write(_ text: String) {
            buffers[buffers.count - 1] += text
        }

        /// Ends the current block, unless inside a cell or list item, where
        /// blocks run together.
        private mutating func breakBlock() {
            if inCell { write(" ") } else if lists.isEmpty { write("\n\n") }
        }

        /// Text outside `<pre>`: entities decoded, then re-escaped so they
        /// stay text, and lines unindented so indentation never reads as a
        /// Markdown code block. Newlines stay: models write Markdown inside
        /// HTML ("<div>\n- one\n- two\n</div>").
        private func flowing(_ text: String) -> String {
            // Code spans show their text as is: no entity is decoded in them.
            if codeDepth > 0 { return HTMLBlock.decoded(text).replacingOccurrences(of: "\n", with: " ") }
            let escaped = HTMLBlock.decoded(text)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            let lines = escaped.components(separatedBy: "\n").enumerated().map { index, line in
                index == 0 ? line : String(line.drop { $0 == " " || $0 == "\t" })
            }
            let joined = lines.joined(separator: inCell ? " " : "\n")
            return inCell ? joined.replacingOccurrences(of: "|", with: "\\|") : joined
        }

        private mutating func open(_ name: String, attributes: String) {
            if preDepth > 0 {
                if name == "pre" { preDepth += 1 }
                // <pre><code class="language-swift">: the fence's language.
                if name == "code", let kind = HTMLBlock.attribute("class", in: attributes),
                   let language = kind.split(separator: " ").first(where: { $0.hasPrefix("language-") }) {
                    preLanguage = String(language.dropFirst("language-".count))
                }
                return
            }
            switch name {
            case "p", "div", "section", "article", "header", "footer", "main", "nav", "aside", "figure", "details":
                breakBlock()
            case "summary":
                breakBlock()
                write("**")
            case "h1", "h2", "h3", "h4", "h5", "h6":
                breakBlock()
                if !inCell { write(String(repeating: "#", count: Int(name.dropFirst()) ?? 1) + " ") }
            case "ul", "ol":
                if lists.isEmpty && !inCell { write("\n\n") }
                lists.append((name == "ol", 0))
            case "li":
                guard !lists.isEmpty else { breakBlock(); write("- "); return }
                lists[lists.count - 1].count += 1
                let indent = lists.dropLast().map { $0.ordered ? "   " : "  " }.joined()
                let list = lists[lists.count - 1]
                write("\n" + indent + (list.ordered ? "\(list.count). " : "- "))
            case "table":
                breakBlock()
                tables.append(Table())
            case "thead":
                if !tables.isEmpty { tables[tables.count - 1].isHeaderRow = true }
            case "tbody", "tfoot":
                if !tables.isEmpty { tables[tables.count - 1].isHeaderRow = false }
            case "tr":
                if !tables.isEmpty { tables[tables.count - 1].rows.append([]) }
            case "th", "td":
                guard !tables.isEmpty else { return }
                if tables[tables.count - 1].rows.isEmpty { tables[tables.count - 1].rows.append([]) }
                if name == "th" && tables[tables.count - 1].rows.count == 1 { tables[tables.count - 1].isHeaderRow = true }
                buffers.append("")
            case "blockquote":
                breakBlock()
                quoteDepths.append(buffers.count)
                buffers.append("")
            case "pre":
                breakBlock()
                preDepth = 1
                preLanguage = nil
                buffers.append("")
            case "code":
                codeDepth += 1
                if codeDepth == 1 { write("`") }
            case "hr":
                breakBlock()
                write("---")
                breakBlock()
            case "img":
                if let alt = HTMLBlock.attribute("alt", in: attributes), !alt.isEmpty { write("*\(alt)*") }
            case _ where HTMLBlock.inlineTags.contains(name):
                write("<\(name)\(attributes)>")
            default:
                break
            }
        }

        private mutating func close(_ name: String) {
            if preDepth > 0 {
                if name == "pre" { preDepth -= 1 } else { return }
                guard preDepth == 0 else { return }
                // `keepingLineBreaks` ran over the whole reply first and gave
                // these lines hard breaks; code keeps its lines as written.
                var code = buffers.removeLast().replacingOccurrences(of: "  \n", with: "\n")
                while code.hasPrefix("\n") { code.removeFirst() }
                while code.hasSuffix("\n") { code.removeLast() }
                write("```\(preLanguage ?? "")\n\(code)\n```")
                breakBlock()
                return
            }
            switch name {
            case "p", "div", "section", "article", "header", "footer", "main", "nav", "aside", "figure", "details",
                 "h1", "h2", "h3", "h4", "h5", "h6":
                breakBlock()
            case "summary":
                write("**")
                breakBlock()
            case "ul", "ol":
                guard !lists.isEmpty else { return }
                lists.removeLast()
                if lists.isEmpty { breakBlock() }
            case "th", "td":
                guard !tables.isEmpty, buffers.count > 1 + quoteDepths.count else { return }
                let cell = buffers.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
                tables[tables.count - 1].rows[tables[tables.count - 1].rows.count - 1].append(cell)
            case "tr":
                if let table = tables.last, table.isHeaderRow, !table.rows.isEmpty {
                    tables[tables.count - 1].headerRows = table.rows.count
                }
            case "thead":
                if !tables.isEmpty { tables[tables.count - 1].isHeaderRow = false }
            case "table":
                guard let table = tables.popLast() else { return }
                // A cell left open by a cut-off chunk.
                while buffers.count > 1 + quoteDepths.count { _ = buffers.removeLast() }
                write(Self.markdownTable(table))
                breakBlock()
            case "blockquote":
                guard let depth = quoteDepths.popLast() else { return }
                while buffers.count > depth + 1 { _ = buffers.removeLast() }
                let quote = buffers.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
                write(quote.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n"))
                breakBlock()
            case "code":
                guard codeDepth > 0 else { return }
                codeDepth -= 1
                if codeDepth == 0 { write("`") }
            case _ where HTMLBlock.inlineTags.contains(name):
                write("</\(name)>")
            default:
                break
            }
        }

        /// A Markdown table; with no header row the first row serves as one.
        static func markdownTable(_ table: Table) -> String {
            let rows = table.rows.filter { !$0.isEmpty }
            guard let first = rows.first else { return "" }
            let width = rows.map(\.count).max() ?? first.count
            func line(_ cells: [String]) -> String {
                "| " + (cells + Array(repeating: "", count: width - cells.count)).joined(separator: " | ") + " |"
            }
            let divider = "|" + Array(repeating: "---|", count: width).joined()
            return ([line(first), divider] + rows.dropFirst().map(line)).joined(separator: "\n")
        }
    }

    // MARK: Helpers

    /// Whether a name inside angle brackets reads as an HTML tag: models
    /// write tags in lowercase (or, rarely, all caps). A capitalized or
    /// single capital name is a generic type, as in `Future<Output>` or
    /// `Array<U>`, and stays text.
    static func isTagName<S: StringProtocol>(_ name: S) -> Bool {
        name == name.lowercased() || (name.count >= 2 && name == name.uppercased())
    }

    /// `name="value"` (or single-quoted) from a tag's attributes.
    static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = try? Regex<(Substring, Substring)>(#"(?i)\b"# + name + #"\s*=\s*["']([^"']*)["']"#)
        guard let pattern, let match = attributes.firstMatch(of: pattern) else { return nil }
        return decoded(String(match.output.1))
    }

    /// The common named entities and every numeric one.
    static func decoded(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
                     "mdash": "—", "ndash": "–", "hellip": "…", "copy": "©", "reg": "®", "trade": "™",
                     "times": "×", "divide": "÷", "deg": "°", "plusmn": "±", "rarr": "→", "larr": "←",
                     "le": "≤", "ge": "≥", "ne": "≠"]
        return text.replacing(#/&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z]+);/#) { match in
            let body = match.output.1
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            if body.hasPrefix("#") {
                return UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            return named[String(body)] ?? String(match.output.0)
        }
    }
}
