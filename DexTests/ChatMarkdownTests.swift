//
//  ChatMarkdownTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import Testing
@testable import Dex

/// Reply Markdown, ported from Sphinx with its tests (less the LaTeX ones).
@Suite("Chat Markdown")
struct ChatMarkdownTests {
    private func plain(_ text: AttributedString) -> String { String(text.characters) }

    private func kinds(_ blocks: [ChatMarkdownBlock]) -> [String] {
        blocks.map { block in
            switch block {
            case .paragraph: "p"
            case .heading(let level, _): "h\(level)"
            case .listItem(let marker, let depth, _): "li(\(marker),\(depth))"
            case .quote: "quote"
            case .code: "code"
            case .table: "table"
            }
        }
    }

    @Test("Paragraphs and headings become separate blocks")
    func headings() {
        let blocks = ChatMarkdown.blocks(from: "## Tuesday\n\nYou made **$120**.\n\nTwo trades.")
        #expect(kinds(blocks) == ["h2", "p", "p"])
        if case .paragraph(let text) = blocks[1] { #expect(plain(text) == "You made $120.") }
    }

    @Test("Bullet and numbered lists keep their markers and nesting")
    func lists() {
        let blocks = ChatMarkdown.blocks(from: "- NQ\n- ES\n  - MES\n\n1. First\n2. Second")
        #expect(kinds(blocks) == ["li(•,1)", "li(•,1)", "li(•,2)", "li(1.,1)", "li(2.,1)"])
    }

    @Test("Code blocks keep their text without the trailing newline")
    func code() {
        let blocks = ChatMarkdown.blocks(from: "```\nnet = 120\n```")
        #expect(blocks == [.code("net = 120")])
    }

    @Test("Quotes are their own block")
    func quote() {
        #expect(kinds(ChatMarkdown.blocks(from: "> Stay patient")) == ["quote"])
    }

    @Test("Tables collect a header and rows of cells")
    func table() {
        let blocks = ChatMarkdown.blocks(from: "| Day | Net |\n|---|---|\n| Mon | 120 |\n| Tue | -40 |")
        guard case .table(let header, let rows) = blocks.first else {
            Issue.record("No table: \(kinds(blocks))")
            return
        }
        #expect(header.map(plain) == ["Day", "Net"])
        #expect(rows.map { $0.map(plain) } == [["Mon", "120"], ["Tue", "-40"]])
    }

    @Test("Empty table cells keep their column")
    func emptyCells() {
        let blocks = ChatMarkdown.blocks(from: "| | A |\n|---|---|\n| x | |\n| y | 2 |")
        guard case .table(let header, let rows) = blocks.first else {
            Issue.record("No table: \(kinds(blocks))")
            return
        }
        #expect(header.map(plain) == ["", "A"])
        #expect(rows.map { $0.map(plain) } == [["x", ""], ["y", "2"]])
    }

    @Test("Single line breaks stay line breaks")
    func lineBreaks() {
        let blocks = ChatMarkdown.blocks(from: "Net: $120\nFees: $4\nTrades: 2")
        #expect(kinds(blocks) == ["p"])
        if case .paragraph(let text) = blocks.first {
            #expect(plain(text).split(whereSeparator: \.isNewline).count == 3)
        }
        // A line already ending in a backslash break keeps it hidden.
        if case .paragraph(let text) = ChatMarkdown.blocks(from: "Net: $120\\\nFees: $4").first {
            #expect(!plain(text).contains("\\"))
            #expect(plain(text).split(whereSeparator: \.isNewline).count == 2)
        }
        // Lists and code blocks are untouched by it.
        #expect(kinds(ChatMarkdown.blocks(from: "- a\n- b")) == ["li(•,1)", "li(•,1)"])
        #expect(ChatMarkdown.blocks(from: "```\na\nb\n```") == [.code("a\nb")])
    }

    @Test("Plain text is one paragraph")
    func plainText() {
        let blocks = ChatMarkdown.blocks(from: "No trades that day.")
        #expect(kinds(blocks) == ["p"])
    }
}
