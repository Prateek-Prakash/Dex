//
//  ChatMarkdown.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

// Markdown for replies, drawn natively. Ported from Sphinx, less its LaTeX
// (Sphinx draws math with SwiftMath; Dex has no packages).
//
// Apple's parser does the work: `AttributedString(markdown:)` with full syntax
// tags every run with the block it belongs to (paragraph, heading, list item,
// quote, code block, table cell). Runs are grouped back into those blocks here,
// and each block is drawn as its own view. Inline styling (bold, italic,
// inline code, links) rides along on the attributed text.
//
// Only replies are rendered this way; the user's own messages show as typed.

enum ChatMarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    /// `marker` is "•" or "3." on an item's first line and empty on the rest.
    case listItem(marker: String, depth: Int, AttributedString)
    case quote(AttributedString)
    case code(String)
    case table(header: [AttributedString], rows: [[AttributedString]])
}

enum ChatMarkdown {
    static func blocks(from source: String) -> [ChatMarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: keepingLineBreaks(source), options: options) else {
            return [.paragraph(AttributedString(source))]
        }

        var blocks: [ChatMarkdownBlock] = []
        var currentID: Int?
        var currentText = AttributedString()
        var currentIntent: PresentationIntent?
        var markedItems = Set<Int>()

        // A table is collected cell by cell and emitted once its last cell is seen.
        // Cells are placed by column: an empty cell has no text run at all, and
        // would otherwise shift the rest of its row left.
        var tableID: Int?
        var tableColumns = 0
        var header: [Int: AttributedString] = [:]
        var rows: [[Int: AttributedString]] = []
        var rowID: Int?

        func flushTable() {
            guard tableID != nil else { return }
            let width = max(tableColumns, ([header.keys.max()] + rows.map { $0.keys.max() }).compactMap { $0 }.max().map { $0 + 1 } ?? 0)
            func filled(_ cells: [Int: AttributedString]) -> [AttributedString] {
                (0..<width).map { cells[$0] ?? AttributedString() }
            }
            blocks.append(.table(header: header.isEmpty ? [] : filled(header), rows: rows.map(filled)))
            tableID = nil
            tableColumns = 0
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
                    if case .table(let columns) = table.kind { tableColumns = columns.count }
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

            for kind in kinds {
                switch kind {
                case .codeBlock:
                    var code = String(currentText.characters)
                    while code.hasSuffix("\n") { code.removeLast() }
                    blocks.append(.code(code))
                    return
                case .header(let level):
                    blocks.append(.heading(level: level, currentText))
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
                blocks.append(.listItem(marker: marker, depth: max(depth, 1), currentText))
                return
            }

            if kinds.contains(.blockQuote) {
                blocks.append(.quote(currentText))
                return
            }
            blocks.append(.paragraph(currentText))
        }

        for run in parsed.runs {
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
        return blocks.filter { block in
            if case .paragraph(let text) = block { return !text.characters.isEmpty }
            return true
        }
    }

    /// Markdown joins a paragraph's lines with spaces, but models write "Net: $120"
    /// and "Fees: $4" on separate lines expecting them to stay separate. Each
    /// such line gets a hard break, leaving code blocks and tables alone.
    static func keepingLineBreaks(_ text: String) -> String {
        var inFence = false
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            // Lines already ending in a break (`\` or two spaces) are left alone:
            // two more spaces after a `\` would leave it showing.
            guard !inFence, !trimmed.isEmpty, !trimmed.hasPrefix("|"),
                  !line.hasSuffix("\\"), !line.hasSuffix("  "),
                  index + 1 < lines.count,
                  !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            lines[index] = line + "  "
        }
        return lines.joined(separator: "\n")
    }
}

struct ChatMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            ForEach(Array(ChatMarkdown.blocks(from: text).enumerated()), id: \.offset) { _, block in
                view(for: block)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func view(for block: ChatMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
        case .heading(let level, let text):
            Text(text)
                .font(level <= 1 ? .title3 : level == 2 ? .headline : .subheadline)
                .fontWeight(.bold)
                .padding(.top, 4.0)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6.0) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16.0, alignment: .trailing)
                Text(text)
            }
            .padding(.leading, CGFloat(depth - 1) * 18.0)
        case .quote(let text):
            Text(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 12.0)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.drawerBorder).frame(width: 3.0)
                }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12.0)
            }
            .background(Color.composerChip, in: RoundedRectangle(cornerRadius: 12.0, style: .continuous))
        case .table(let header, let rows):
            table(header: header, rows: rows)
        }
    }

    private func table(header: [AttributedString], rows: [[AttributedString]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16.0, verticalSpacing: 8.0) {
                if !header.isEmpty {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Rectangle().fill(Color.drawerBorder).frame(height: 1.0).gridCellUnsizedAxes(.horizontal)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(12.0)
        }
        .background(Color.composerChip, in: RoundedRectangle(cornerRadius: 12.0, style: .continuous))
    }
}
