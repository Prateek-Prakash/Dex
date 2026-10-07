//
//  ChatMath.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI
import SwiftMath

// LaTeX math in replies, drawn with SwiftMath. Ported from Sphinx.
//
// `\( … \)` (inline) and `\[ … \]` or `$$ … $$` (display) are math. Single `$`
// is math only where it can't be money, by Pandoc's rules plus one more: the
// opening `$` is followed by a non-space, the closing one follows a non-space
// and isn't followed by a letter or digit ("$SPY/$QQQ" is two tickers), and the
// inside has a letter or one of \ ^ _ =.
// Answers are full of "$52,340 and $148,910", and reading those as math would
// turn everything between two amounts into an equation. Code is never searched
// for math.
//
// Math is taken out before Markdown sees the text, since Markdown treats `\(`
// as an escaped parenthesis. Display math becomes its own block; each inline
// formula is replaced by one placeholder character that carries the formula as
// an attribute and is drawn as an image on the text's baseline.

enum ChatMath {
    /// Stands in for one inline formula inside Markdown text.
    static let placeholder: Character = "\u{E000}"

    enum Segment: Equatable {
        case text(String)
        case display(String)
    }

    /// The text split around display math, outside code fences.
    static func segments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var pending = ""
        for chunk in fenced(text) {
            guard !chunk.isCode else { pending += chunk.text; continue }
            var rest = Substring(chunk.text)
            while let match = firstDisplay(in: rest) {
                pending += rest[..<match.range.lowerBound]
                let latex = match.latex.trimmingCharacters(in: .whitespacesAndNewlines)
                if latex.isEmpty {
                    pending += rest[match.range]
                } else {
                    if !pending.isEmpty { segments.append(.text(pending)) }
                    pending = ""
                    segments.append(.display(latex))
                }
                rest = rest[match.range.upperBound...]
            }
            pending += rest
        }
        if !pending.isEmpty { segments.append(.text(pending)) }
        return segments
    }

    /// The text with each inline formula outside code replaced by a
    /// placeholder, and the formulas in order.
    static func extractingInline(_ text: String) -> (text: String, formulas: [String]) {
        var formulas: [String] = []
        var result = ""
        for chunk in fenced(text) {
            guard !chunk.isCode else { result += chunk.text; continue }
            var rest = Substring(chunk.text)
            while let open = rest.firstRange(of: #/`[^`\n]*`|\\\(|\$/#) {
                result += rest[..<open.lowerBound]
                if rest[open].hasPrefix("`") {
                    // Inline code stays as written.
                    result += rest[open]
                    rest = rest[open.upperBound...]
                    continue
                }
                if rest[open] == "$" {
                    if let dollar = dollarMath(rest[open.lowerBound...]) {
                        formulas.append(dollar.latex)
                        result.append(placeholder)
                        rest = rest[dollar.end...]
                    } else {
                        // Money.
                        result += "$"
                        rest = rest[open.upperBound...]
                    }
                    continue
                }
                let body = rest[open.upperBound...]
                guard let close = body.firstRange(of: #"\)"#) else {
                    result += rest[open.lowerBound...]
                    rest = rest[rest.endIndex...]
                    break
                }
                let latex = body[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if latex.isEmpty {
                    result += rest[open.lowerBound..<close.upperBound]
                } else {
                    formulas.append(latex)
                    result.append(placeholder)
                }
                rest = body[close.upperBound...]
            }
            result += rest
        }
        return (result, formulas)
    }

    /// Tags each placeholder in parsed Markdown with its formula, in order.
    static func attach(_ formulas: [String], to text: inout AttributedString) {
        guard !formulas.isEmpty else { return }
        var index = 0
        var position = text.startIndex
        while position < text.endIndex, index < formulas.count {
            let next = text.characters.index(after: position)
            if text.characters[position] == placeholder {
                text[position..<next][ChatMathAttribute.self] = formulas[index]
                index += 1
            }
            position = next
        }
    }

    // MARK: Scanning

    private struct Chunk {
        let text: String
        let isCode: Bool
    }

    /// The text cut into code fences and everything else, kept in order.
    private static func fenced(_ text: String) -> [Chunk] {
        var chunks: [Chunk] = []
        var current = ""
        var fence = CodeFence()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let piece = (line.offset == 0 ? "" : "\n") + line.element
            let wasOpen = fence.isOpen
            if fence.isFenceLine(line.element) {
                if wasOpen {
                    current += piece
                    chunks.append(Chunk(text: current, isCode: true))
                    current = ""
                } else {
                    if !current.isEmpty { chunks.append(Chunk(text: current, isCode: false)) }
                    current = piece
                }
            } else {
                current += piece
            }
        }
        if !current.isEmpty { chunks.append(Chunk(text: current, isCode: fence.isOpen)) }
        return chunks
    }

    /// `$…$` starting at `text`'s first character when it reads as math, with
    /// where the formula ends.
    static func dollarMath(_ text: Substring) -> (latex: String, end: Substring.Index)? {
        let body = text.dropFirst()
        guard let first = body.first, !first.isWhitespace, first != "$",
              let close = body.firstIndex(where: { $0 == "$" || $0.isNewline }), body[close] == "$" else { return nil }
        let inside = body[..<close]
        let after = body.index(after: close)
        guard let last = inside.last, !last.isWhitespace,
              after == body.endIndex || !(body[after].isNumber || body[after].isLetter),
              inside.contains(where: { $0.isLetter || "\\^_=".contains($0) }) else { return nil }
        return (String(inside), after)
    }

    private static func firstDisplay(in text: Substring) -> (range: Range<Substring.Index>, latex: Substring)? {
        let brackets = text.firstMatch(of: #/\\\[([\s\S]+?)\\\]/#)
        let dollars = text.firstMatch(of: #/\$\$([\s\S]+?)\$\$/#)
        let first = [brackets, dollars].compactMap { $0 }.min { $0.range.lowerBound < $1.range.lowerBound }
        return first.map { ($0.range, $0.output.1) }
    }
}

/// Tracks ``` and ~~~ code fences line by line, as CommonMark does: a fence
/// closes only on a line of its own character, at least as long as its
/// opening, with nothing after it; a backtick fence's opening line holds no
/// other backtick.
struct CodeFence {
    private var open: (character: Character, count: Int)?

    var isOpen: Bool { open != nil }

    /// Feeds the next line; true when it opens or closes a fence.
    mutating func isFenceLine<S: StringProtocol>(_ line: S) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard let first = trimmed.first, first == "`" || first == "~" else { return false }
        let count = trimmed.prefix { $0 == first }.count
        guard count >= 3 else { return false }
        if let open {
            guard first == open.character, count >= open.count,
                  trimmed.dropFirst(count).allSatisfy(\.isWhitespace) else { return false }
            self.open = nil
        } else {
            // "```npm i``` then run it" is inline code, not a fence: a
            // backtick fence's info string can't hold a backtick.
            if first == "`" && trimmed.dropFirst(count).contains("`") { return false }
            open = (first, count)
        }
        return true
    }
}

/// The LaTeX source of an inline formula's placeholder.
enum ChatMathAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "Dex.chatMath"
}

// MARK: - Drawing

/// Formulas drawn once per look and kept: answers redraw on every streamed piece.
@MainActor
enum ChatMathRenderer {
    struct Rendered {
        let image: UIImage
        /// How far the baseline sits above the image's bottom edge.
        let descent: CGFloat
    }

    private static let cache = NSCache<NSString, Box>()
    private final class Box {
        let value: Rendered?
        init(_ value: Rendered?) { self.value = value }
    }

    /// Nil when SwiftMath can't parse or doesn't support the LaTeX.
    static func render(_ latex: String, size: CGFloat, color: UIColor, display: Bool) -> Rendered? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let key = "\(display ? "D" : "T")|\(size)|\(red),\(green),\(blue),\(alpha)|\(latex)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        var image = MathImage(latex: latex, fontSize: size, textColor: color,
                              labelMode: display ? .display : .text, textAlignment: .left)
        image.font = .notoSansFont
        let (error, drawn, layout) = image.asImage()
        let rendered = error == nil ? drawn.map { Rendered(image: $0, descent: layout?.descent ?? 0) } : nil
        cache.setObject(Box(rendered), forKey: key)
        return rendered
    }
}

extension Text {
    /// Attributed Markdown text with its inline formulas drawn on the baseline,
    /// its inline code in chips (see `InlineCodeRenderer`) and its `<sup>` and
    /// `<sub>` text raised and lowered; a formula
    /// SwiftMath can't draw shows as its LaTeX source.
    @MainActor
    static func chat(_ text: AttributedString, size: CGFloat, color: UIColor) -> Text {
        guard text.runs.contains(where: { $0[ChatMathAttribute.self] != nil || InlineCode.isCode($0) || $0[InlineHTML.Script.self] != nil })
        else { return Text(text) }
        var result = Text(verbatim: "")
        for run in text.runs {
            let piece: Text
            if let latex = run[ChatMathAttribute.self] {
                // Identical neighbours merge into one run: one formula per placeholder.
                let count = text[run.range].characters.count
                let one: Text
                if let rendered = ChatMathRenderer.render(latex, size: size, color: color, display: false) {
                    one = Text(Image(uiImage: rendered.image)).baselineOffset(-rendered.descent)
                } else {
                    one = Text(verbatim: latex).font(.system(size: size - 2, design: .monospaced))
                }
                piece = (1..<max(count, 1)).reduce(one) { joined, _ in Text("\(joined)\(one)") }
            } else if let script = run[InlineHTML.Script.self] {
                // Smaller, and raised or lowered by a share of the text's size.
                piece = Text(AttributedString(text[run.range]))
                    .font(.system(size: size * 0.72))
                    .baselineOffset(script == .superscript ? size * 0.38 : -size * 0.12)
            } else if InlineCode.isCode(run) {
                piece = InlineCode.text(String(text[run.range].characters), size: size)
            } else {
                piece = Text(AttributedString(text[run.range]))
            }
            result = Text("\(result)\(piece)")
        }
        return result
    }
}

/// A display formula on its own line, scrolling sideways when wider than
/// the screen.
struct ChatMathBlockView: View {
    let latex: String
    let size: CGFloat
    let color: UIColor

    var body: some View {
        if let rendered = ChatMathRenderer.render(latex, size: size, color: color, display: true) {
            let image = Image(uiImage: rendered.image).padding(.vertical, 2)
            ViewThatFits(in: .horizontal) {
                image
                ScrollView(.horizontal, showsIndicators: false) { image }
            }
        } else {
            Text(verbatim: latex)
                .font(.system(.callout, design: .monospaced))
        }
    }
}
