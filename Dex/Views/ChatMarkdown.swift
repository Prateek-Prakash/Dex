//
//  ChatMarkdown.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import HighlightSwift
import SwiftUI

// Markdown for replies, drawn natively. Ported from Sphinx.
//
// Apple's parser does the work: `AttributedString(markdown:)` with full syntax
// tags every run with the block it belongs to (paragraph, heading, list item,
// quote, code block, table cell). Runs are grouped back into those blocks here,
// and each block is drawn as its own view. Inline styling (bold, italic,
// inline code, links) rides along on the attributed text; inline code gets
// Claude's chip (see InlineCode). LaTeX math is taken out first and drawn by
// SwiftMath (see ChatMath). Code blocks are colored by HighlightSwift.
//
// Only replies are rendered this way; the user's own messages show as typed.

enum ChatMarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    /// `marker` is "•" or "3." on an item's first line and empty on the rest.
    case listItem(marker: String, depth: Int, AttributedString)
    case quote(AttributedString)
    /// `language` is the fence's hint ("swift" in ```swift), when given.
    case code(language: String?, String)
    /// `alignments` per column, from the divider row (`:--`, `:-:`, `--:`).
    case table(header: [AttributedString], rows: [[AttributedString]], alignments: [TableAlignment])
    /// A display formula's LaTeX source.
    case math(String)
    /// A task list item (`- [ ] todo`, `- [x] done`), drawn with a checkbox.
    case task(checked: Bool, depth: Int, AttributedString)
    /// A horizontal rule (`---` or `<hr>`).
    case rule
    /// A GitHub-style alert: a quote opening with `[!NOTE]`, `[!WARNING]`…,
    /// holding the quote's blocks (paragraphs, lists, code).
    indirect case callout(Callout, [ChatMarkdownBlock])
}

enum TableAlignment: Equatable {
    case leading, center, trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

enum Callout: String, CaseIterable {
    case note, tip, important, warning, caution

    var title: String {
        switch self {
        case .note: "Note"
        case .tip: "Tip"
        case .important: "Important"
        case .warning: "Warning"
        case .caution: "Caution"
        }
    }

    /// GitHub's alert colors.
    var color: Color {
        switch self {
        case .note: Color(light: 0x0969DA, dark: 0x4493F8)
        case .tip: Color(light: 0x1A7F37, dark: 0x3FB950)
        case .important: Color(light: 0x8250DF, dark: 0xAB7DF8)
        case .warning: Color(light: 0x9A6700, dark: 0xD29922)
        case .caution: Color(light: 0xCF222E, dark: 0xF85149)
        }
    }

    /// The alert a quote's first paragraph opens with, and the paragraph
    /// without its marker.
    static func parse(_ text: AttributedString) -> (Callout, AttributedString)? {
        let characters = String(text.characters)
        guard let match = characters.prefixMatch(of: #/\s*\[!([A-Za-z]+)\][ \t]*\n?\s*/#),
              let callout = Callout(rawValue: match.output.1.lowercased()) else { return nil }
        let count = characters[match.range].count
        var rest = text
        rest.removeSubrange(rest.startIndex..<rest.index(rest.startIndex, offsetByCharacters: count))
        return (callout, rest)
    }
}

enum ChatMarkdown {
    static func blocks(from text: String) -> [ChatMarkdownBlock] {
        ChatMath.segments(EmojiShortcodes.replace(Footnotes.resolve(text))).flatMap { segment -> [ChatMarkdownBlock] in
            switch segment {
            case .display(let latex): [.math(latex)]
            case .text(let text): markdownBlocks(from: text)
            }
        }
    }

    /// Markdown blocks, with inline formulas tagged on their placeholders.
    /// `depth` counts HTML blocks rewritten as Markdown (see `HTMLBlock`),
    /// so one that rewrites to HTML again can't recurse forever.
    private static func markdownBlocks(from source: String, depth: Int = 0) -> [ChatMarkdownBlock] {
        let (text, formulas) = ChatMath.extractingInline(source)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var parsed = try? AttributedString(markdown: keepingLineBreaks(text), options: options) else {
            return [.paragraph(AttributedString(source))]
        }
        ChatMath.attach(formulas, to: &parsed)
        InlineHTML.apply(to: &parsed)
        // Inline code a model escaped for HTML.
        for run in parsed.runs.reversed() where InlineCode.isCode(run) {
            let code = String(parsed[run.range].characters)
            let unescaped = unescapingOverEscaped(code)
            if unescaped != code {
                parsed.characters.replaceSubrange(run.range, with: unescaped)
            }
        }
        // The app's tint is the text color: links get the system link blue,
        // underlined, so they read apart from underlined text.
        for run in parsed.runs where run.link != nil {
            parsed[run.range].foregroundColor = Color(uiColor: .link)
            parsed[run.range].underlineStyle = .single
        }

        var blocks: [ChatMarkdownBlock] = []
        var currentID: Int?
        var currentText = AttributedString()
        var currentIntent: PresentationIntent?
        var markedItems = Set<Int>()
        /// The quote an alert opened, so its later paragraphs join it.
        var calloutQuote: Int?

        // A table is collected cell by cell and emitted once its last cell is seen.
        // Cells are placed by column: an empty cell has no text run at all, and
        // would otherwise shift the rest of its row left.
        var tableID: Int?
        var tableColumns = 0
        var tableAlignments: [TableAlignment] = []
        var header: [Int: AttributedString] = [:]
        var rows: [[Int: AttributedString]] = []
        var rowID: Int?

        func flushTable() {
            guard tableID != nil else { return }
            let width = max(tableColumns, ([header.keys.max()] + rows.map { $0.keys.max() }).compactMap { $0 }.max().map { $0 + 1 } ?? 0)
            func filled(_ cells: [Int: AttributedString]) -> [AttributedString] {
                (0..<width).map { cells[$0] ?? AttributedString() }
            }
            let alignments = (0..<width).map { $0 < tableAlignments.count ? tableAlignments[$0] : .leading }
            blocks.append(.table(header: header.isEmpty ? [] : filled(header), rows: rows.map(filled), alignments: alignments))
            tableID = nil
            tableColumns = 0
            tableAlignments = []
            header = [:]
            rows = []
            rowID = nil
        }

        func flushBlock() {
            defer {
                currentID = nil
                currentText = AttributedString()
                currentIntent = nil
            }
            guard let intent = currentIntent, currentID != nil else { return }
            let kinds = intent.components.map(\.kind)

            if let table = intent.components.first(where: { if case .table = $0.kind { true } else { false } }) {
                if tableID != table.identity {
                    flushTable()
                    tableID = table.identity
                    if case .table(let columns) = table.kind {
                        tableColumns = columns.count
                        tableAlignments = columns.map { column in
                            switch column.alignment {
                            case .center: .center
                            case .right: .trailing
                            default: .leading
                            }
                        }
                    }
                }
                let row = intent.components.first { component in
                    switch component.kind {
                    case .tableRow, .tableHeaderRow: true
                    default: false
                    }
                }
                var column = 0
                for kind in kinds {
                    if case .tableCell(let index) = kind { column = index }
                }
                if kinds.contains(.tableHeaderRow) {
                    header[column] = currentText
                } else {
                    if row?.identity != rowID { rows.append([:]); rowID = row?.identity }
                    rows[rows.count - 1][column] = currentText
                }
                return
            }
            flushTable()

            // Inside an alert's quote, blocks go into the alert.
            let quoteID = intent.components.first(where: { $0.kind == .blockQuote })?.identity
            func emit(_ block: ChatMarkdownBlock) {
                if let quoteID, quoteID == calloutQuote, case .callout(let callout, var children)? = blocks.last {
                    children.append(block)
                    blocks[blocks.count - 1] = .callout(callout, children)
                } else {
                    blocks.append(block)
                }
            }

            for kind in kinds {
                switch kind {
                case .codeBlock(let hint):
                    var code = Self.unescapingOverEscaped(String(currentText.characters))
                    while code.hasSuffix("\n") { code.removeLast() }
                    let language = hint?.trimmingCharacters(in: .whitespaces)
                    emit(.code(language: language?.isEmpty == false ? language : nil, code))
                    return
                case .header(let level):
                    emit(.heading(level: level, currentText))
                    return
                case .thematicBreak:
                    emit(.rule)
                    return
                default:
                    continue
                }
            }

            if let item = intent.components.first(where: { if case .listItem = $0.kind { true } else { false } }) {
                let depth = kinds.filter { $0 == .orderedList || $0 == .unorderedList }.count
                var marker = ""
                if !markedItems.contains(item.identity) {
                    markedItems.insert(item.identity)
                    // The innermost list decides the marker.
                    let ordered = kinds.first { $0 == .orderedList || $0 == .unorderedList } == .orderedList
                    if case .listItem(let ordinal) = item.kind {
                        marker = ordered ? "\(ordinal)." : "•"
                    }
                }
                // GitHub task lists: "[ ] " or "[x] " opening an item's first line.
                if !marker.isEmpty, let (checked, rest) = Self.task(currentText) {
                    emit(.task(checked: checked, depth: max(depth, 1), rest))
                    return
                }
                emit(.listItem(marker: marker, depth: max(depth, 1), currentText))
                return
            }

            if let quoteID {
                if quoteID == calloutQuote {
                    emit(.paragraph(currentText))
                    return
                }
                if let (callout, body) = Callout.parse(currentText) {
                    calloutQuote = quoteID
                    blocks.append(.callout(callout, body.characters.isEmpty ? [] : [.paragraph(body)]))
                    return
                }
                emit(.quote(currentText))
                return
            }
            emit(.paragraph(currentText))
        }

        // Block-level HTML arrives as raw runs outside any block, split where
        // a formula's placeholder sits; gathered whole, it's rewritten as
        // Markdown with its formulas put back as LaTeX for the second pass.
        var html = ""
        func flushHTML() {
            guard !html.isEmpty else { return }
            defer { html = "" }
            if depth < 2 {
                blocks += markdownBlocks(from: HTMLBlock.markdown(from: html), depth: depth + 1)
            } else {
                let text = HTMLBlock.tokens(html).compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
                blocks.append(.paragraph(AttributedString(HTMLBlock.decoded(text).trimmingCharacters(in: .whitespacesAndNewlines))))
            }
        }

        for run in parsed.runs {
            if run.inlinePresentationIntent?.contains(.blockHTML) == true {
                flushBlock()
                flushTable()
                if let latex = run[ChatMathAttribute.self] {
                    html += String(repeating: "\\(" + latex + "\\)", count: parsed[run.range].characters.count)
                } else {
                    html += String(parsed[run.range].characters)
                }
                continue
            }
            flushHTML()
            let intent = run.presentationIntent
            // The innermost component names the block a run belongs to.
            let id = intent?.components.first?.identity
            if id != currentID {
                flushBlock()
                currentID = id
                currentIntent = intent
            }
            currentText.append(AttributedString(parsed[run.range]))
        }
        flushBlock()
        flushTable()
        flushHTML()
        return blocks.filter { block in
            if case .paragraph(let text) = block { return !text.characters.isEmpty }
            return true
        }
    }

    /// Code a model escaped for HTML (`&lt;div&gt;`), though code shows its
    /// text as is, decoded. Only when the code holds no raw `<`: real code
    /// that shows an entity on purpose (`<p>&lt;b&gt;</p>`) has raw tags too.
    static func unescapingOverEscaped(_ code: String) -> String {
        guard !code.contains("<"),
              code.range(of: #"&(lt|gt|amp|quot|apos|#39);"#, options: .regularExpression) != nil else { return code }
        return code
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Whether `text` opens with a task box, and the text after it.
    static func task(_ text: AttributedString) -> (checked: Bool, rest: AttributedString)? {
        let characters = String(text.characters)
        guard let match = characters.prefixMatch(of: #/\[([ xX])\][ \t]+/#) else { return nil }
        var rest = text
        rest.removeSubrange(rest.startIndex..<rest.index(rest.startIndex, offsetByCharacters: characters[match.range].count))
        return (match.output.1 != " ", rest)
    }

    /// Markdown joins a paragraph's lines with spaces, but models write "Net: $120"
    /// and "Fees: $4" on separate lines expecting them to stay separate. Each
    /// such line gets a hard break, leaving code blocks and tables alone.
    static func keepingLineBreaks(_ text: String) -> String {
        var fence = CodeFence()
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fence.isFenceLine(line) { continue }
            // Lines already ending in a break (`\` or two spaces) are left alone:
            // two more spaces after a `\` would leave it showing.
            guard !fence.isOpen, !trimmed.isEmpty, !trimmed.hasPrefix("|"),
                  !line.hasSuffix("\\"), !line.hasSuffix("  "),
                  index + 1 < lines.count,
                  !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            lines[index] = line + "  "
        }
        return lines.joined(separator: "\n")
    }
}

/// Equal when the text is: a transcript redraws on every streamed piece,
/// and only the reply whose text changed needs parsing again. Appearance
/// and Dynamic Type still redraw it through its environment.
struct ChatMarkdownView: View, Equatable {
    let text: String

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    // Formulas are images drawn at a point size: these follow Dynamic Type
    // with the text styles their blocks use.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17.0
    @ScaledMetric(relativeTo: .title3) private var title3Size: CGFloat = 20.0
    @ScaledMetric(relativeTo: .subheadline) private var subheadlineSize: CGFloat = 15.0

    /// Formula ink for the current appearance; SwiftMath takes a fixed color.
    private func ink(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
    }

    /// Text drawn with its inline formulas, which take the text's size.
    private func line(_ text: AttributedString, size: CGFloat, color: UIColor = .label) -> Text {
        Text.chat(text, size: size, color: ink(color))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            ForEach(Array(ChatMarkdown.blocks(from: text).enumerated()), id: \.offset) { _, block in
                view(for: block)
                    // Text holding a formula image otherwise settles for one
                    // truncated line instead of wrapping.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textRenderer(InlineCodeRenderer(fill: .inlineCodeFill, border: .inlineCodeBorder,
                                         hairline: 1.0 / displayScale))
    }

    @ViewBuilder
    private func view(for block: ChatMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            line(text, size: bodySize)
        case .heading(let level, let text):
            line(text, size: level <= 1 ? title3Size : level == 2 ? bodySize : subheadlineSize)
                .font(level <= 1 ? .title3 : level == 2 ? .headline : .subheadline)
                .fontWeight(.bold)
                .padding(.top, 4.0)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6.0) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16.0, alignment: .trailing)
                line(text, size: bodySize)
            }
            .padding(.leading, CGFloat(depth - 1) * 18.0)
        case .task(let checked, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                TaskBox(isChecked: checked, size: bodySize)
                line(text, size: bodySize)
            }
            .padding(.leading, CGFloat(depth - 1) * 18.0)
            .accessibilityElement(children: .combine)
            .accessibilityValue(checked ? "Done" : "Not Done")
        case .quote(let text):
            line(text, size: bodySize, color: .secondaryLabel)
                .foregroundStyle(.secondary)
                .padding(.leading, 12.0)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.drawerBorder).frame(width: 3.0)
                }
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .table(let header, let rows, let alignments):
            table(header: header, rows: rows, alignments: alignments)
        case .math(let latex):
            ChatMathBlockView(latex: latex, size: bodySize, color: ink(.label))
        case .callout(let callout, let children):
            VStack(alignment: .leading, spacing: 8.0) {
                Text(callout.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(callout.color)
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    // Type-erased: a view built from blocks can't contain itself by type.
                    AnyView(view(for: child))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12.0)
            .padding(.leading, 15.0)
            .padding(.trailing, 12.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(callout.color.opacity(0.08))
            .overlay(alignment: .leading) {
                Rectangle().fill(callout.color).frame(width: 3.0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12.0, style: .continuous))
        case .rule:
            Rectangle()
                .fill(Color.drawerBorder)
                .frame(height: 1.0)
                .padding(.vertical, 6.0)
        }
    }

    private func table(header: [AttributedString], rows: [[AttributedString]], alignments: [TableAlignment]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16.0, verticalSpacing: 8.0) {
                if !header.isEmpty {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { column, cell in
                            line(cell, size: subheadlineSize, color: .secondaryLabel)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(textAlignment(alignments, column))
                                .gridColumnAlignment(alignment(alignments, column))
                        }
                    }
                    Rectangle().fill(Color.drawerBorder).frame(height: 1.0).gridCellUnsizedAxes(.horizontal)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            line(cell, size: subheadlineSize)
                                .font(.subheadline)
                                .monospacedDigit()
                                .multilineTextAlignment(textAlignment(alignments, column))
                                .gridColumnAlignment(alignment(alignments, column))
                        }
                    }
                }
            }
            .padding(12.0)
        }
        .background(Color.composerChip, in: RoundedRectangle(cornerRadius: 12.0, style: .continuous))
    }

    private func alignment(_ alignments: [TableAlignment], _ column: Int) -> HorizontalAlignment {
        column < alignments.count ? alignments[column].horizontal : .leading
    }

    private func textAlignment(_ alignments: [TableAlignment], _ column: Int) -> TextAlignment {
        switch column < alignments.count ? alignments[column] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// A fenced code block, colored by HighlightSwift (highlight.js, GitHub's
/// theme) in the fence's language, or a guessed one without a hint. Shows
/// plain until colored; while a reply streams, the colored part stays and
/// only the newest text is plain until the next pass.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var colored: CodeColoring.Result?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(shown)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(12.0)
        }
        .background(Color.composerChip, in: RoundedRectangle(cornerRadius: 12.0, style: .continuous))
        .task(id: CodeColoring.Key(code: code, language: language, isDark: colorScheme == .dark)) {
            let key = CodeColoring.Key(code: code, language: language, isDark: colorScheme == .dark)
            if let hit = CodeColoring.cached(key) {
                colored = hit
                return
            }
            // Streaming text changes many times a second; color once it pauses.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            colored = await CodeColoring.color(key)
        }
    }

    private var shown: AttributedString {
        CodeColoring.shown(code: code, colored: colored, isDark: colorScheme == .dark)
    }
}

enum CodeColoring {
    struct Key: Hashable, Sendable {
        let code: String
        let language: String?
        let isDark: Bool
    }

    struct Result: Sendable {
        let source: String
        let isDark: Bool
        let text: AttributedString
    }

    private static let highlight = Highlight()
    @MainActor private static var cache: [Key: Result] = [:]

    /// Colored text kept as views come and go; lists rebuild rows on scroll.
    @MainActor
    static func cached(_ key: Key) -> Result? {
        cache[key]
    }

    @MainActor
    static func color(_ key: Key) async -> Result? {
        let colors: HighlightColors = key.isDark ? .dark(.github) : .light(.github)
        var text: AttributedString?
        if let language = key.language {
            text = try? await highlight.attributedText(key.code, language: language, colors: colors)
        }
        // No hint, or one highlight.js doesn't know ("jsx", "shell-session").
        if text == nil {
            text = try? await highlight.attributedText(key.code, colors: colors)
        }
        guard var text else { return nil }
        // Only the colors: the theme's page background stays out.
        text.uiKit.backgroundColor = nil
        let result = Result(source: key.code, isDark: key.isDark, text: text)
        if cache.count > 200 { cache.removeAll() }
        cache[key] = result
        return result
    }

    /// The colored text when it fits what's shown now: as is, or followed by
    /// the part that streamed in after it was colored. Otherwise plain.
    /// HighlightSwift trims the code it colors, so the trimmed ends go back
    /// on uncolored.
    static func shown(code: String, colored: Result?, isDark: Bool) -> AttributedString {
        guard let colored, colored.isDark == isDark, code.hasPrefix(colored.source) else { return AttributedString(code) }
        let source = colored.source
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, String(colored.text.characters) == trimmed,
              let range = source.range(of: trimmed) else { return AttributedString(code) }
        return AttributedString(String(source[..<range.lowerBound]))
            + colored.text
            + AttributedString(String(source[range.upperBound...]))
            + AttributedString(String(code.dropFirst(source.count)))
    }
}

/// A task list's checkbox, drawn rather than an icon: a rounded square,
/// filled with a check when done. Sized to the text, its bottom on the
/// text's baseline.
private struct TaskBox: View {
    let isChecked: Bool
    let size: CGFloat

    var body: some View {
        let side = size * 0.9
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
                .fill(isChecked ? Color.primary : Color.clear)
            RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
                .strokeBorder(isChecked ? Color.primary : Color.secondary, lineWidth: 1.5)
            if isChecked {
                Checkmark()
                    .stroke(Color.appBackground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .padding(side * 0.24)
            }
        }
        .frame(width: side, height: side)
        // Sits like a capital letter: bottom on the baseline.
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - size * 0.02 }
    }

    private struct Checkmark: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
            return path
        }
    }
}

