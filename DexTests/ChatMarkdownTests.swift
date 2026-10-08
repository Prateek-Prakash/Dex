//
//  ChatMarkdownTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import SwiftUI
import Testing
@testable import Dex

/// Reply Markdown and LaTeX, ported from Sphinx with its tests.
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
            case .math(let latex): "math(\(latex))"
            case .rule: "hr"
            case .task(let checked, let depth, _): "task(\(checked ? "x" : " "),\(depth))"
            case .callout(let callout, _): "callout(\(callout.rawValue))"
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
        #expect(blocks == [.code(language: nil, "net = 120")])
    }

    @Test("Quotes are their own block")
    func quote() {
        #expect(kinds(ChatMarkdown.blocks(from: "> Stay patient")) == ["quote"])
    }

    @Test("Tables collect a header and rows of cells")
    func table() {
        let blocks = ChatMarkdown.blocks(from: "| Day | Net |\n|---|---|\n| Mon | 120 |\n| Tue | -40 |")
        guard case .table(let header, let rows, _) = blocks.first else {
            Issue.record("No table: \(kinds(blocks))")
            return
        }
        #expect(header.map(plain) == ["Day", "Net"])
        #expect(rows.map { $0.map(plain) } == [["Mon", "120"], ["Tue", "-40"]])
    }

    @Test("Empty table cells keep their column")
    func emptyCells() {
        let blocks = ChatMarkdown.blocks(from: "| | A |\n|---|---|\n| x | |\n| y | 2 |")
        guard case .table(let header, let rows, _) = blocks.first else {
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
        #expect(ChatMarkdown.blocks(from: "```\na\nb\n```") == [.code(language: nil, "a\nb")])
    }

    @Test("A Markdown rule is a rule, not a paragraph")
    func rule() {
        #expect(kinds(ChatMarkdown.blocks(from: "Above\n\n---\n\nBelow")) == ["p", "hr", "p"])
    }

    @Test("Plain text is one paragraph")
    func plainText() {
        let blocks = ChatMarkdown.blocks(from: "No trades that day.")
        #expect(kinds(blocks) == ["p"])
    }

    // MARK: Math

    /// The formulas tagged on a block's placeholders, in order.
    private func formulas(_ text: AttributedString) -> [String] {
        text.runs.compactMap { $0[ChatMathAttribute.self] }
    }

    @Test("Display math becomes its own block, from \\[ \\] or $$ $$")
    func displayMath() {
        let blocks = ChatMarkdown.blocks(from: "Sharpe:\n\\[ S = \\frac{R}{\\sigma} \\]\nThen $$x^2$$ done.")
        #expect(kinds(blocks) == ["p", "math(S = \\frac{R}{\\sigma})", "p", "math(x^2)", "p"])
    }

    @Test("Inline math is tagged on one placeholder per formula")
    func inlineMath() throws {
        let blocks = ChatMarkdown.blocks(from: "Risk is \\(\\sigma\\) and **reward** is \\(\\mu\\).")
        guard case .paragraph(let text) = try #require(blocks.first) else { Issue.record("not a paragraph"); return }
        #expect(formulas(text) == ["\\sigma", "\\mu"])
        #expect(plain(text) == "Risk is \u{E000} and reward is \u{E000}.")
    }

    @Test("A single $ is money, never math")
    func dollarsStayText() throws {
        let blocks = ChatMarkdown.blocks(from: "APEX-1 has $52,340 and TOPSTEP-2 has $148,910.")
        guard case .paragraph(let text) = try #require(blocks.first) else { Issue.record("not a paragraph"); return }
        #expect(blocks.count == 1)
        #expect(formulas(text).isEmpty)
        #expect(plain(text) == "APEX-1 has $52,340 and TOPSTEP-2 has $148,910.")
    }

    @Test("Single-dollar math is read only where it can't be money")
    func singleDollar() {
        #expect(ChatMath.extractingInline("So $E = mc^2$ holds.").formulas == ["E = mc^2"])
        #expect(ChatMath.extractingInline("Risk $\\sigma$ and $x_i$.").formulas == ["\\sigma", "x_i"])
        for money in ["APEX-1 has $52,340 and TOPSTEP-2 has $148,910.",
                      "Range $100-$200 today.",
                      "Up +$120 vs -$40.",
                      "Paid $5$ flat.",
                      "Between $ 5 and $ 6.",
                      "Cost $1,200$, fine.",
                      "The $SPY/$QQQ ratio.",
                      "Spread $BTC-$ETH widened."] {
            let extracted = ChatMath.extractingInline(money)
            #expect(extracted.formulas.isEmpty, "\(money)")
            #expect(extracted.text == money)
        }
    }

    @Test("Code is never searched for math")
    func codeUntouched() {
        #expect(ChatMarkdown.blocks(from: "```\n\\[ x \\]\n```") == [.code(language: nil, "\\[ x \\]")])
        let inline = ChatMath.extractingInline("Type `\\(x\\)` to get \\(x\\).")
        #expect(inline.text == "Type `\\(x\\)` to get \u{E000}.")
        #expect(inline.formulas == ["x"])
    }

    @Test("Unclosed or empty delimiters stay as text")
    func unclosed() {
        #expect(ChatMath.extractingInline("Half \\(x + y").formulas.isEmpty)
        #expect(ChatMath.extractingInline("Empty \\( \\) here").formulas.isEmpty)
        #expect(ChatMath.segments("Still streaming \\[ x =") == [.text("Still streaming \\[ x =")])
    }

    @Test("Math works inside lists and tables")
    func mathInBlocks() throws {
        guard case .listItem(_, _, let item) = try #require(ChatMarkdown.blocks(from: "- Edge \\(E\\)").first) else {
            Issue.record("not a list item"); return
        }
        #expect(formulas(item) == ["E"])
        guard case .table(_, let rows, _) = try #require(ChatMarkdown.blocks(from: "| a | b |\n|---|---|\n| \\(x\\) | 2 |").first) else {
            Issue.record("not a table"); return
        }
        #expect(formulas(rows[0][0]) == ["x"])
    }

    @Test("SwiftMath draws valid LaTeX and refuses what it can't parse")
    @MainActor func rendering() {
        let drawn = ChatMathRenderer.render("\\frac{a}{b}", size: 15, color: .white, display: false)
        #expect(drawn != nil && (drawn?.image.size.width ?? 0) > 0)
        #expect(ChatMathRenderer.render("\\frac{a", size: 15, color: .white, display: false) == nil)
    }

    // MARK: Code

    @Test("A fence's language hint rides on its code block")
    func codeLanguage() {
        #expect(ChatMarkdown.blocks(from: "```swift\nlet x = 1\n```") == [.code(language: "swift", "let x = 1")])
    }

    @Test("Inline code runs are found for their chips")
    func inlineCodeRuns() throws {
        guard case .paragraph(let text) = try #require(ChatMarkdown.blocks(from: "Run `make` now.").first) else {
            Issue.record("not a paragraph"); return
        }
        let code = text.runs.filter { InlineCode.isCode($0) }.map { String(text[$0.range].characters) }
        #expect(code == ["make"])
    }

    @Test("Colored code shows only while it matches the code")
    func codeColoringFits() {
        var colored = AttributedString("let x")
        colored.foregroundColor = .red
        let result = CodeColoring.Result(source: "  let x\n", isDark: false, text: colored)
        // Trimmed ends come back; newer streamed text follows uncolored.
        let shown = CodeColoring.shown(code: "  let x\nlet y", colored: result, isDark: false)
        #expect(String(shown.characters) == "  let x\nlet y")
        #expect(shown.runs.contains { $0.foregroundColor == .red })
        // A different appearance or a rewritten block falls back to plain.
        #expect(!CodeColoring.shown(code: "  let x\n", colored: result, isDark: true).runs.contains { $0.foregroundColor == .red })
        #expect(!CodeColoring.shown(code: "var z", colored: result, isDark: false).runs.contains { $0.foregroundColor == .red })
        #expect(String(CodeColoring.shown(code: "var z", colored: nil, isDark: false).characters) == "var z")
    }

    @Test("HighlightSwift colors code without changing it")
    @MainActor func highlighting() async throws {
        let code = "let total = items.reduce(0, +) // sum"
        let result = try #require(await CodeColoring.color(.init(code: code, language: "swift", isDark: false)))
        #expect(String(result.text.characters) == code)
        #expect(Set(result.text.runs.compactMap { $0.uiKit.foregroundColor }).count > 1)
        let shown = CodeColoring.shown(code: code, colored: result, isDark: false)
        #expect(String(shown.characters) == code)
    }

    // MARK: Inline HTML

    private func paragraph(_ markdown: String) throws -> AttributedString {
        guard case .paragraph(let text) = try #require(ChatMarkdown.blocks(from: markdown).first) else {
            Issue.record("not a paragraph"); return AttributedString()
        }
        return text
    }

    @Test("Underline tags underline their text and disappear")
    func underline() throws {
        let text = try paragraph("Read <u>this</u> and <INS>that</INS> now.")
        #expect(plain(text) == "Read this and that now.")
        let underlined = text.runs.filter { $0.underlineStyle != nil }.map { String(text[$0.range].characters) }
        #expect(underlined == ["this", "that"])
    }

    @Test("Strikethrough, bold, italic and line break tags")
    func otherTags() throws {
        let text = try paragraph("<del>old</del> <b>bold</b> <em>soft</em><br>next")
        #expect(plain(text) == "old bold soft\nnext")
        #expect(text.runs.contains { $0.strikethroughStyle != nil && String(text[$0.range].characters) == "old" })
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true && String(text[$0.range].characters) == "bold" })
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true && String(text[$0.range].characters) == "soft" })
    }

    @Test("Unknown tags and stray closes stay as written")
    func unknownTags() throws {
        #expect(plain(try paragraph("Use Vec<T> here.")) == "Use Vec<T> here.")
        #expect(plain(try paragraph("A <widget>b</widget> c")) == "A <widget>b</widget> c")
        #expect(plain(try paragraph("Stray </u> close")) == "Stray </u> close")
    }

    @Test("A tag still open mid-stream styles the rest")
    func openTag() throws {
        let text = try paragraph("Start <u>under so far")
        #expect(plain(text) == "Start under so far")
        #expect(text.runs.contains { $0.underlineStyle != nil })
    }

    @Test("Inline tags: superscript, subscript, highlight, keys and links")
    func moreInlineTags() throws {
        let text = try paragraph("E = mc<sup>2</sup>, H<sub>2</sub>O, <mark>key</mark>, <kbd>Esc</kbd>, <a href=\"https://ollama.com\">site</a>")
        #expect(plain(text) == "E = mc2, H2O, key, Esc, site")
        func run(_ word: String) -> AttributedString.Runs.Run? {
            text.runs.first { String(text[$0.range].characters) == word }
        }
        #expect(run("2")?[InlineHTML.Script.self] == .superscript)
        #expect(text.runs.contains { $0[InlineHTML.Script.self] == .subscript })
        #expect(run("key")?.backgroundColor != nil)
        #expect(run("Esc").map(InlineCode.isCode) == true)
        #expect(run("site")?.link == URL(string: "https://ollama.com"))
        #expect(run("site")?.underlineStyle != nil)
    }

    @Test("A link without an address keeps its text and loses its tags")
    func bareAnchor() throws {
        #expect(plain(try paragraph("See <a name=\"x\">here</a> now")) == "See here now")
    }

    @Test("HTML inside code stays exactly as written")
    func htmlInCode() throws {
        let text = try paragraph("Use `<u>x</u>` and `<div>` literally.")
        let code = text.runs.filter { InlineCode.isCode($0) }.map { String(text[$0.range].characters) }
        #expect(code == ["<u>x</u>", "<div>"])
        #expect(!text.runs.contains { $0.underlineStyle != nil })
        #expect(ChatMarkdown.blocks(from: "```html\n<div><b>x</b></div>\n```") == [.code(language: "html", "<div><b>x</b></div>")])
    }

    // MARK: HTML blocks

    @Test("Block HTML draws instead of vanishing")
    func htmlBlocksDraw() {
        let blocks = ChatMarkdown.blocks(from: "Before\n\n<div>\nHello <b>there</b>\n</div>\n\nAfter")
        #expect(kinds(blocks) == ["p", "p", "p"])
        if case .paragraph(let text) = blocks[1] {
            #expect(plain(text) == "Hello there")
            #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        }
    }

    @Test("Headings, paragraphs, lists and rules")
    func htmlStructure() {
        let blocks = ChatMarkdown.blocks(from: "<h2>Plan</h2><p>Two steps:</p><ol><li>Pull</li><li>Run <ul><li>fast</li></ul></li></ol><hr><p>Done &amp; dusted</p>")
        #expect(kinds(blocks) == ["h2", "p", "li(1.,1)", "li(2.,1)", "li(•,2)", "hr", "p"])
        if case .paragraph(let text) = blocks.last { #expect(plain(text) == "Done & dusted") }
    }

    @Test("HTML tables become tables")
    func htmlTable() {
        let blocks = ChatMarkdown.blocks(from: "<table><thead><tr><th>Model</th><th>Size</th></tr></thead><tbody><tr><td>gemma4</td><td>12 | B</td></tr></tbody></table>")
        guard case .table(let header, let rows, _) = blocks.first else {
            Issue.record("No table: \(kinds(blocks))")
            return
        }
        #expect(header.map(plain) == ["Model", "Size"])
        #expect(rows.map { $0.map(plain) } == [["gemma4", "12 | B"]])
    }

    @Test("Quotes, pre blocks and details")
    func htmlOtherBlocks() {
        let blocks = ChatMarkdown.blocks(from: """
        <blockquote>Stay curious</blockquote>
        <pre><code class="language-swift">let x = 1 &lt; 2
        print(x)</code></pre>
        <details><summary>More</summary>Hidden text</details>
        """)
        #expect(kinds(blocks) == ["quote", "code", "p", "p"])
        #expect(blocks[1] == .code(language: "swift", "let x = 1 < 2\nprint(x)"))
    }

    @Test("Unknown tags drop and keep their text; escaped text stays text")
    func htmlUnknown() {
        let blocks = ChatMarkdown.blocks(from: "<section><custom-tag>Kept</custom-tag> &lt;b&gt;not bold&lt;/b&gt;</section>")
        guard case .paragraph(let text) = blocks.first else { Issue.record("\(kinds(blocks))"); return }
        #expect(plain(text) == "Kept <b>not bold</b>")
        #expect(!text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test("A block cut off mid-stream still draws what has arrived")
    func htmlCutOff() {
        let blocks = ChatMarkdown.blocks(from: "<table><tr><th>A</th></tr><tr><td>1")
        #expect(kinds(blocks) == ["table"])
        #expect(!ChatMarkdown.blocks(from: "<div><p>Partial").isEmpty)
    }

    // MARK: Fixes from review

    @Test("~~~ fences are code: no math, no hard breaks")
    func tildeFences() {
        #expect(ChatMarkdown.blocks(from: "~~~bash\necho $a_1$\nls\n~~~") == [.code(language: "bash", "echo $a_1$\nls")])
        #expect(ChatMath.extractingInline("~~~\n\\(x\\)\n~~~").formulas.isEmpty)
    }

    @Test("A code fence inside an HTML block stays code, untouched")
    func fenceInHTML() {
        let blocks = ChatMarkdown.blocks(from: """
        <details>
        <summary>Example</summary>

        ```html
        <b>a & b</b>
        ```
        </details>
        """)
        #expect(blocks.contains(.code(language: "html", "<b>a & b</b>")))
        #expect(kinds(blocks).first == "p")
    }

    @Test("Formulas inside an HTML block still draw")
    func mathInHTML() throws {
        let blocks = ChatMarkdown.blocks(from: "<div>Area is \\(\\pi r^2\\) here</div>")
        guard case .paragraph(let text) = try #require(blocks.first) else { Issue.record("\(kinds(blocks))"); return }
        #expect(formulas(text) == ["\\pi r^2"])
    }

    @Test("A tag left open ends with its paragraph")
    func openTagEndsWithParagraph() {
        let blocks = ChatMarkdown.blocks(from: "Wrap it in a <b> tag.\n\nThis stays plain.")
        guard case .paragraph(let second) = blocks.last else { Issue.record("\(kinds(blocks))"); return }
        #expect(!second.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test("Spans and other quiet tags disappear and keep their text; <code> is code")
    func quietTags() throws {
        let text = try paragraph("A <span style=\"color:red\">red</span> <small>note</small> and <code>x()</code>, not Vec<T>.")
        #expect(plain(text) == "A red note and x(), not Vec<T>.")
        #expect(text.runs.contains { InlineCode.isCode($0) && String(text[$0.range].characters) == "x()" })
    }

    @Test("Links are blue and underlined")
    func linkColor() throws {
        let text = try paragraph("See [Ollama](https://ollama.com).")
        let link = try #require(text.runs.first { $0.link != nil })
        #expect(link.foregroundColor == Color.link)
        #expect(link.underlineStyle != nil)
    }

    @Test("GitHub alerts become callouts; their later paragraphs join them")
    func callouts() {
        let blocks = ChatMarkdown.blocks(from: "> [!WARNING]\n> Back up first.\n>\n> Then run it.\n\n> Plain quote")
        #expect(kinds(blocks) == ["callout(warning)", "quote"])
        if case .callout(_, let children) = blocks.first {
            #expect(children.compactMap { if case .paragraph(let text) = $0 { plain(text) } else { nil } } == ["Back up first.", "Then run it."])
        }
        #expect(kinds(ChatMarkdown.blocks(from: "> [!note] Inline text")) == ["callout(note)"])
        #expect(kinds(ChatMarkdown.blocks(from: "> [!BOGUS] text")) == ["quote"])
    }

    @Test("The reply view is equal exactly when its text is")
    func markdownViewEquality() {
        #expect(ChatMarkdownView(text: "a") == ChatMarkdownView(text: "a"))
        #expect(ChatMarkdownView(text: "a") != ChatMarkdownView(text: "b"))
    }

    @Test("Task list items get checkboxes; other brackets stay text")
    func taskLists() {
        let blocks = ChatMarkdown.blocks(from: "- [ ] Pull model\n- [x] Install **Ollama**\n  - [X] nested\n- [link] stays\n- plain")
        #expect(kinds(blocks) == ["task( ,1)", "task(x,1)", "task(x,2)", "li(•,1)", "li(•,1)"])
        if case .task(_, _, let text) = blocks[1] {
            #expect(plain(text) == "Install Ollama")
            #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        }
        if case .listItem(_, _, let text) = blocks[3] { #expect(plain(text) == "[link] stays") }
    }

    // MARK: GitHub Flavored Markdown

    @Test("Strikethrough and autolinks come from the parser")
    func gfmInline() throws {
        let text = try paragraph("~~gone~~ at www.ollama.com or me@x.com")
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.strikethrough) == true })
        #expect(text.runs.compactMap(\.link).map(\.absoluteString) == ["http://www.ollama.com", "mailto:me@x.com"])
        #expect(text.runs.filter { $0.link != nil }.allSatisfy { $0.underlineStyle != nil })
    }

    @Test("Table columns keep their alignment")
    func tableAlignment() {
        let blocks = ChatMarkdown.blocks(from: "| L | C | R | D |\n|:--|:-:|--:|---|\n| a | b | c | d |")
        guard case .table(_, _, let alignments) = blocks.first else { Issue.record("\(kinds(blocks))"); return }
        #expect(alignments == [.leading, .center, .trailing, .leading])
    }

    @Test("Script and style blocks drop with their content")
    func disallowedHTML() {
        let blocks = ChatMarkdown.blocks(from: "<div>Shown<script>alert(1)</script><style>p { color: red }</style></div>")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks.first { #expect(plain(text) == "Shown") }
    }

    @Test("Footnotes number in order of use and gather at the end")
    func footnotes() {
        let markdown = "First[^b] then[^a] and[^b] again, but `[^a]` is code.\n\n[^a]: Note A\n    continued.\n[^b]: Note B\n[^unused]: Never shown"
        let resolved = Footnotes.resolve(markdown)
        #expect(resolved == "First<sup>1</sup> then<sup>2</sup> and<sup>1</sup> again, but `[^a]` is code.\n\n---\n\n1. Note B\n2. Note A continued.")
        #expect(kinds(ChatMarkdown.blocks(from: markdown)) == ["p", "hr", "li(1.,1)", "li(2.,1)"])
    }

    @Test("Footnotes leave code and unmatched references alone")
    func footnotesUntouched() {
        #expect(Footnotes.resolve("A[^x] with no note") == "A[^x] with no note")
        let fenced = "```\n[^a]: in code\n```\nText[^a]\n\n[^a]: Real"
        #expect(Footnotes.resolve(fenced).hasPrefix("```\n[^a]: in code\n```\nText<sup>1</sup>"))
    }

    // MARK: Fixes from the second review

    @Test("<code> in an HTML block shows its text as written")
    func codeInHTMLBlock() {
        let blocks = ChatMarkdown.blocks(from: "<div>Use <code>a && b</code> or <code>Vec&lt;T&gt;</code></div>")
        guard case .paragraph(let text) = blocks.first else { Issue.record("\(kinds(blocks))"); return }
        let code = text.runs.filter { InlineCode.isCode($0) }.map { String(text[$0.range].characters) }
        #expect(code == ["a && b", "Vec<T>"])
    }

    @Test("Generic type names are never tags")
    func genericsStayText() throws {
        #expect(plain(try paragraph("returns Future<Output> quickly")) == "returns Future<Output> quickly")
        let text = try paragraph("Array<U> and impl<S> stay plain")
        #expect(plain(text) == "Array<U> and impl<S> stay plain")
        #expect(!text.runs.contains { $0.underlineStyle != nil || $0.strikethroughStyle != nil })
        #expect(plain(try paragraph("All caps <STRONG>works</STRONG> too")) == "All caps works too")
        #expect(plain(try paragraph("Single <B> is a generic")) == "Single <B> is a generic")
        #expect(HTMLBlock.tokens("<div>Future<Output></div>") == [.open("div", attributes: ""), .text("Future"), .text("<Output>"), .close("div")])
    }

    @Test("A self-closing skipped tag skips nothing after it")
    func selfClosingSkipped() {
        let blocks = ChatMarkdown.blocks(from: "<div><iframe src=\"x\" />Still here</div>")
        guard case .paragraph(let text) = blocks.first else { Issue.record("\(kinds(blocks))"); return }
        #expect(plain(text) == "Still here")
    }

    @Test("Lists, code and headings inside an alert stay inside it")
    func calloutChildren() {
        let blocks = ChatMarkdown.blocks(from: "> [!TIP]\n> Steps:\n> - one\n> - two\n>\n> ```\n> ollama ps\n> ```\n>\n> Done.\n\nAfter")
        #expect(kinds(blocks) == ["callout(tip)", "p"])
        if case .callout(_, let children) = blocks.first {
            #expect(kinds(children) == ["p", "li(•,1)", "li(•,1)", "code", "p"])
        }
    }

    @Test("Inline triple backticks don't open a fence")
    func inlineTripleBackticks() {
        #expect(ChatMath.extractingInline("```npm i``` then \\(x\\)").formulas == ["x"])
        var fence = CodeFence()
        let inline = fence.isFenceLine("```npm i``` then run it")
        let opening = fence.isFenceLine("```swift")
        #expect(!inline)
        #expect(opening)
    }

    @Test("Footnotes wait while a code block is still open")
    func footnotesWaitForFence() {
        let streaming = "Text[^a]\n\n[^a]: Note\n\n```swift\nlet x"
        #expect(Footnotes.resolve(streaming) == streaming)
    }

    // MARK: Over-escaped code and emoji

    @Test("Code a model escaped for HTML is decoded, real entities stay")
    func overEscapedCode() throws {
        #expect(ChatMarkdown.blocks(from: "```\n&lt;div> Test &lt;/div>\n```") == [.code(language: nil, "<div> Test </div>")])
        #expect(ChatMarkdown.blocks(from: "```html\n<p>&lt;b&gt;</p>\n```") == [.code(language: "html", "<p>&lt;b&gt;</p>")])
        let text = try paragraph("Use `&lt;div&gt;` and `a &amp;&amp; b` but `x &lt; y` too")
        let code = text.runs.filter { InlineCode.isCode($0) }.map { String(text[$0.range].characters) }
        #expect(code == ["<div>", "a && b", "x < y"])
        #expect(ChatMarkdown.unescapingOverEscaped("plain") == "plain")
    }

    @Test("GitHub emoji shortcodes become emoji")
    func emojiShortcodes() {
        #expect(EmojiShortcodes.table.count > 1_800)
        #expect(EmojiShortcodes.replace("Ship it :rocket: :+1: :100:") == "Ship it 🚀 👍 💯")
        #expect(EmojiShortcodes.replace(":tada::tada:") == ":tada::tada:")
        #expect(EmojiShortcodes.replace("(:smile:)") == "(😄)")
    }

    @Test("Ordinary colons and code never change")
    func emojiLeftAlone() {
        for text in ["At 10:30:45 today", "std::vector::size", "ratio 1:100:20", "Not :a_real_one: here",
                     "Case :Smile: stays", "`:rocket:` in code", "word:rocket: joined", "http://x.com/:smile:"] {
            #expect(EmojiShortcodes.replace(text) == text, "\(text)")
        }
        #expect(EmojiShortcodes.replace("```\n:rocket:\n```\n:rocket:") == "```\n:rocket:\n```\n🚀")
        #expect(kinds(ChatMarkdown.blocks(from: "Done :white_check_mark:")) == ["p"])
    }
}

