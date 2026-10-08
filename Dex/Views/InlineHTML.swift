//
//  InlineHTML.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// The inline HTML models write where Markdown has no syntax: underline
/// (`<u>`, `<ins>`, since `__x__` is bold), strikethrough, bold, italic,
/// superscript and subscript, highlight (`<mark>`), keys (`<kbd>`, drawn as
/// inline code, like `<code>`), links (`<a href>`) and line breaks. Apple's
/// parser leaves such tags in the text as raw HTML runs; here they style the
/// text between them and disappear. Other real HTML tags that carry no
/// meaning here (`<span>`, `<small>`, `<font>`) just disappear. Anything
/// else, like the `<T>` in `Vec<T>`, stays exactly as written. A tag left
/// open ends with its paragraph. Code is never touched: the parser hands it
/// over as code, not HTML.
enum InlineHTML {
    private enum Style {
        case underline, strikethrough, bold, italic, superscript, `subscript`, highlight, key
        case link(URL)
        /// An `<a>` without a usable address: pairs with its close, styles nothing.
        case none
    }

    /// Superscript or subscript text, sized and raised by `Text.chat`, which
    /// knows the text's size.
    enum Script: String, AttributedStringKey, Codable {
        typealias Value = Script
        static let name = "Dex.script"
        case superscript, `subscript`
    }

    private static let styles: [String: Style] = [
        "u": .underline, "ins": .underline,
        "s": .strikethrough, "del": .strikethrough, "strike": .strikethrough,
        "b": .bold, "strong": .bold,
        "i": .italic, "em": .italic,
        "sup": .superscript, "sub": .subscript,
        "mark": .highlight, "kbd": .key, "code": .key, "tt": .key, "samp": .key,
    ]

    /// HTML tags dropped without a trace, open or close, keeping their text.
    private static let quiet: Set<String> = [
        "span", "small", "big", "font", "abbr", "acronym", "cite", "q", "time", "var",
        "dfn", "bdi", "bdo", "wbr", "label", "center", "nobr", "data", "output",
    ]

    /// `<mark>`'s highlight.
    static let highlight = Color.textHighlight

    static func apply(to text: inout AttributedString) {
        guard text.runs.contains(where: isHTML) else { return }
        var result = AttributedString()
        // Open tags, innermost last; a close tag ends its nearest match.
        var open: [(name: String, style: Style)] = []
        var block: Int?
        for run in text.runs {
            // A tag left open ("wrap it in a <b> tag") ends with its paragraph.
            let runBlock = run.presentationIntent?.components.first?.identity
            if runBlock != block {
                open.removeAll()
                block = runBlock
            }
            let source = AttributedString(text[run.range])
            // Neighbouring tags ("</em><br>") arrive as one run.
            let pieces = isHTML(run) ? tags(in: String(source.characters)) : nil
            guard let pieces else {
                result += styled(source, open)
                continue
            }
            // The run's block (paragraph, list item, cell) rides along, so
            // what replaces a tag stays in that block.
            let attributes = source.runs.first?.attributes ?? AttributeContainer()
            for raw in pieces {
                if let tag = tag(raw) {
                    if quiet.contains(tag.name) {
                        continue
                    }
                    if tag.name == "br" {
                        var lineBreak = AttributedString("\n", attributes: attributes)
                        lineBreak.inlinePresentationIntent = nil
                        result += lineBreak
                        continue
                    }
                    if tag.isClose, let index = open.lastIndex(where: { $0.name == tag.name }) {
                        open.remove(at: index)
                        continue
                    }
                    if !tag.isClose, let style = style(for: tag) {
                        open.append((tag.name, style))
                        continue
                    }
                }
                // Any other tag stays as written.
                result += styled(AttributedString(raw, attributes: attributes), open)
            }
        }
        text = result
    }

    private static func style(for tag: (name: String, attributes: String, isClose: Bool)) -> Style? {
        guard tag.name == "a" else { return styles[tag.name] }
        return HTMLBlock.attribute("href", in: tag.attributes).flatMap { URL(string: $0) }.map(Style.link) ?? Style.none
    }

    /// `piece` in the styles of the tags still open.
    private static func styled(_ piece: AttributedString, _ open: [(name: String, style: Style)]) -> AttributedString {
        var piece = piece
        func addIntent(_ intent: InlinePresentationIntent) {
            piece.inlinePresentationIntent = (piece.inlinePresentationIntent ?? []).union(intent)
        }
        for (_, style) in open {
            switch style {
            case .underline: piece.underlineStyle = .single
            case .strikethrough: piece.strikethroughStyle = .single
            case .bold: addIntent(.stronglyEmphasized)
            case .italic: addIntent(.emphasized)
            case .superscript: piece[Script.self] = .superscript
            case .subscript: piece[Script.self] = .subscript
            case .highlight: piece.backgroundColor = highlight
            case .key: addIntent(.code)
            case .link(let url): piece.link = url
            case .none: break
            }
        }
        return piece
    }

    /// An HTML run cut into its tags, or nil when it holds anything else.
    private static func tags(in text: String) -> [String]? {
        let matches = text.matches(of: #/<[^<>]*>/#)
        guard !matches.isEmpty, matches.map({ $0.output.count }).reduce(0, +) == text.count else { return nil }
        return matches.map { String($0.output) }
    }

    private static func isHTML(_ run: AttributedString.Runs.Run) -> Bool {
        run.inlinePresentationIntent?.contains(.inlineHTML) == true
    }

    /// `<u>`, `</u>`, `<br/>` or `<a href="…">`, by lowercased name.
    private static func tag(_ text: String) -> (name: String, attributes: String, isClose: Bool)? {
        guard let match = text.wholeMatch(of: #/<\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)([^<>]*?)/?\s*>/#),
              HTMLBlock.isTagName(match.output.2) else { return nil }
        return (match.output.2.lowercased(), String(match.output.3), !match.output.1.isEmpty)
    }
}
