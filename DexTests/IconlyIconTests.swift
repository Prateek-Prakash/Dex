//
//  IconlyIconTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation
import SwiftUI
import Testing
@testable import Dex

struct IconlyIconTests {
    // Every glyph sits centered and inside the 24-unit box. Its visible extent
    // (path bounds plus half the stroke on each side) either fills the box or
    // was shrunk to match the round icons' optical size.
    @Test(arguments: Iconly.allCases)
    func glyphCentersInsideItsBox(_ icon: Iconly) {
        let bounds = extent(icon)
        #expect(!bounds.isEmpty)
        #expect(max(bounds.width, bounds.height) <= 24.05)
        #expect(abs(bounds.midX - 12) < 0.05)
        #expect(abs(bounds.midY - 12) < 0.05)
    }

    // All icons read the same size: no glyph's optical size (the side of a
    // square with its stroked convex hull's area) exceeds the round icons'.
    // A glyph below it must fill the box, as open shapes (Menu) do.
    @Test(arguments: Iconly.allCases)
    func glyphMatchesTheRoundIconsOpticalSize(_ icon: Iconly) {
        let reference = optical(.info)
        let size = optical(icon)
        #expect(size <= reference * 1.01, "\(icon) reads bigger than the round icons")
        if size < reference * 0.99 {
            #expect(abs(max(extent(icon).width, extent(icon).height) - 24) < 0.05,
                    "\(icon) reads smaller than the round icons without filling the box")
        }
    }

    // One line weight for every icon: Iconly's 1.5 on a glyph spanning 18 of 24,
    // so glyphs that are small in their source (Close) don't draw heavier.
    @Test func everyIconSharesOneLineWeight() {
        #expect(abs(Iconly.line - 1.5 * 24 / 19.5) < 0.001)
    }

    // Below 24pt weight follows sqrt(size / 24); above, it grows in proportion.
    @Test func lineWeightFollowsSquareRootBelow24ThenProportional() {
        let fill = IconlyIcon.fill
        let base = IconlyIcon.lineWidth(size: 24, fill: fill)
        for size in [10.0, 12, 14, 18, 20] {
            #expect(abs(IconlyIcon.lineWidth(size: size, fill: fill) - base * (size / 24).squareRoot()) < 0.0001)
        }
        #expect(abs(IconlyIcon.lineWidth(size: 52, fill: fill) - base * 52 / 24) < 0.0001)
    }

    // Each context's size is part of the design: changing one resizes every
    // icon in that context, so it should be a deliberate edit here too.
    @Test func contextPoints() {
        #expect(IconlyIcon.Context.action.points == 24)
        #expect(IconlyIcon.Context.tile.points == 24)
        #expect(IconlyIcon.Context.field.points == 20)
        #expect(IconlyIcon.Context.menu.points == 20)
        #expect(IconlyIcon.Context.row.points == 16)
        #expect(IconlyIcon.Context.inlineButton.points == 14)
        #expect(IconlyIcon.Context.disclosure.points == 12)
        #expect(IconlyIcon.Context.custom(30).points == 30)
    }

    @Test func parserReadsEveryCommand() {
        let bounds = IconlyPath.parse("M0 0 L10 0 C10 5 5 10 0 10 Z M20 20 L22 22").boundingRect
        #expect(abs(bounds.minX) < 0.001)
        #expect(abs(bounds.maxX - 22) < 0.001)
        #expect(abs(bounds.maxY - 22) < 0.001)
    }

    // Icons come only from Iconly: no SF Symbols in the app (an approved
    // exception would be marked `// iconly-exception:` on the line above; Dex
    // has none since the main screen's mark is drawn in code); call sites
    // name a context rather than a raw size, and every `.custom` escape hatch
    // says why on the line above.
    @Test func callSitesUseIconlyAndContexts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Dex")
        let walker = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))

        var scanned = 0
        var exceptions = 0
        var violations: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if url.path.hasSuffix("Helpers/IconlyIcon.swift") { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            let lines = text.components(separatedBy: "\n")
            let name = url.lastPathComponent
            for (index, line) in lines.enumerated() {
                if line.contains("systemName:") || line.contains("systemImage:") {
                    let previous = index > 0 ? lines[index - 1] : ""
                    if previous.range(of: #"//[ \t]*iconly-exception:[ \t]*\S"#, options: .regularExpression) != nil {
                        exceptions += 1
                    } else {
                        violations.append("\(name):\(index + 1): SF Symbol, use IconlyIcon")
                    }
                }
                if line.contains("IconlyIcon("), line.contains("size:") {
                    violations.append("\(name):\(index + 1): raw size, use a Context")
                }
                if line.range(of: #"(?<![\w)\]])\.custom\("#, options: .regularExpression) != nil {
                    let previous = index > 0 ? lines[index - 1] : ""
                    if !previous.contains("// icon-size:") {
                        violations.append("\(name):\(index + 1): .custom without // icon-size: comment above")
                    }
                }
            }
        }
        #expect(scanned >= 10, "Only scanned \(scanned) files")
        #expect(exceptions == 0, "Dex uses no SF Symbols, found \(exceptions)")
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }

    /// Filled (Bold) glyphs have no stroke to add.
    private func line(_ icon: Iconly) -> Double {
        Iconly.filled.contains(icon) ? 0 : Iconly.line
    }

    private func extent(_ icon: Iconly) -> CGRect {
        IconlyPath.parse(icon.path).boundingRect.insetBy(dx: -line(icon) / 2, dy: -line(icon) / 2)
    }

    // Mirrors `optical` in Tools/iconly-paths.py: hull of the path's points
    // (curves sampled), grown by half the stroke.
    private func optical(_ icon: Iconly) -> Double {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        IconlyPath.parse(icon.path).forEach { element in
            switch element {
            case .move(let p), .line(let p):
                points.append(p)
                current = p
            case .curve(let p, let c1, let c2):
                for i in 1...16 {
                    let t = CGFloat(i) / 16, u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    points.append(CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * p.x,
                                          y: a * current.y + b * c1.y + c * c2.y + d * p.y))
                }
                current = p
            case .quadCurve(let p, _):
                points.append(p)
                current = p
            case .closeSubpath:
                break
            }
        }
        let hull = convexHull(points)
        var area = 0.0, perimeter = 0.0
        for i in hull.indices {
            let a = hull[i], b = hull[(i + hull.count - 1) % hull.count]
            area += a.x * b.y - b.x * a.y
            perimeter += hypot(a.x - b.x, a.y - b.y)
        }
        let r = line(icon) / 2
        return (abs(area) / 2 + perimeter * r + .pi * r * r).squareRoot()
    }

    private func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
