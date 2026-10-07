//
//  InlineCode.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// Inline code in replies, like Claude's: monospaced, tinted, in a rounded
/// chip with a hairline border. Text can't pad or box part of itself, so the
/// code is tagged with `InlineCode.Chip` and `InlineCodeRenderer` draws the
/// chip behind it; narrow spaces on each side give the chip room.
enum InlineCode {
    struct Chip: TextAttribute {}

    /// Narrow no-break space: the chip's padding inside the text. No-break,
    /// so a wrap never strands the padding as an empty chip on its own.
    static let padding = "\u{202F}"

    static func isCode(_ run: AttributedString.Runs.Run) -> Bool {
        run.inlinePresentationIntent?.contains(.code) == true
    }

    static func text(_ code: String, size: CGFloat) -> Text {
        Text(verbatim: padding + code + padding)
            // A step under the text around it, as monospaced type runs large.
            .font(.system(size: size * 0.88, design: .monospaced))
            .foregroundStyle(Color.inlineCodeText)
            .customAttribute(Chip())
    }
}

/// Draws a chip behind each stretch of `InlineCode.Chip` text, line by line,
/// so code that wraps gets a chip on each line.
struct InlineCodeRenderer: TextRenderer {
    let fill: Color
    let border: Color
    let hairline: CGFloat

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for rect in Self.chipRects(line) {
                let chip = RoundedRectangle(cornerRadius: 5.0, style: .continuous)
                    .path(in: rect.insetBy(dx: 0, dy: -1.0))
                context.fill(chip, with: .color(fill))
                context.stroke(chip, with: .color(border), lineWidth: hairline)
            }
            context.draw(line)
        }
    }

    /// Neighbouring chip runs on a line share one chip.
    private static func chipRects(_ line: Text.Layout.Line) -> [CGRect] {
        var rects: [CGRect] = []
        var current: CGRect?
        for run in line {
            if run[InlineCode.Chip.self] != nil {
                let bounds = run.typographicBounds.rect
                current = current.map { $0.union(bounds) } ?? bounds
            } else if let rect = current {
                rects.append(rect)
                current = nil
            }
        }
        if let current { rects.append(current) }
        return rects
    }
}
