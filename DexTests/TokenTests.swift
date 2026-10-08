//
//  TokenTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import Testing

/// Colors, spacing and corner radii come from the token files
/// (`ColorExt.swift`, `Layout.swift`), never written in place. A one-off
/// spacing value says why with `// spacing: <reason>` on the line above.
/// Hierarchical text styles (`.foregroundStyle(.secondary)`) are allowed.
struct TokenTests {
    /// A system hue, or `Color.primary`/`.secondary` as a color. SwiftUI's
    /// hierarchical text styles (`.foregroundStyle(.secondary)`) stay: they
    /// are already levels, and adapt to glass.
    private static let systemColor = #"(?<![\w.])(?:Color\.|\.)(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray|black|white)\b(?!\()|Color\.(?:primary|secondary)\b|\.color\(\.(?:primary|secondary)\)"#
    private static let uiSystemColor = #"(?<![\w])(?:UIColor)?\.(?:system[A-Z]\w*|label|secondaryLabel|tertiaryLabel|quaternaryLabel)\b"#
    private static let colorLiteral = #"Color\((?:light|red|white|hue|uiColor|\.)"#
    private static let rawSpacing = #"(?:\bspacing: |\.padding\((?:\.[a-zA-Z]+, )?|\b(?:top|leading|bottom|trailing): )(?!0\b)\d"#
    private static let rawRadius = #"cornerRadius: \d"#

    @Test func viewsUseTokensOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Dex")
        let walker = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))

        var scanned = 0
        var exceptions = 0
        var violations: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if url.path.hasSuffix("Extensions/ColorExt.swift") || url.path.hasSuffix("Extensions/Layout.swift") { continue }
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            scanned += 1
            let name = url.lastPathComponent
            for (index, line) in lines.enumerated() {
                // Comments and string literals aren't code.
                let code = line.components(separatedBy: "//").first ?? line
                func found(_ pattern: String) -> Bool {
                    code.range(of: pattern, options: .regularExpression) != nil
                }
                if found(Self.systemColor) || found(Self.uiSystemColor) || found(Self.colorLiteral) {
                    violations.append("\(name):\(index + 1): raw color, use a Color token")
                }
                if found(Self.rawRadius) {
                    violations.append("\(name):\(index + 1): raw corner radius, use a Radius token")
                }
                if found(Self.rawSpacing) {
                    let previous = index > 0 ? lines[index - 1] : ""
                    if previous.range(of: #"//[ \t]*spacing:[ \t]*\S"#, options: .regularExpression) != nil {
                        exceptions += 1
                    } else {
                        violations.append("\(name):\(index + 1): raw spacing, use a Space token or say why")
                    }
                }
            }
        }
        #expect(scanned > 20)
        #expect(exceptions > 0)
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }
}
