//
//  TileRow.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// A list row like Claude's Projects rows: a rounded tile with a glyph,
/// level with the name, and a subtitle under the name; the name stays on
/// one line. Folders, Organize and a folder's chats all use it, so they
/// look the same. A check, when set, sits at the right edge.
struct TileRow: View {
    let icon: Iconly
    let title: String
    let subtitle: String
    var isChecked = false

    /// Sizes measured from Claude's Projects list; follow Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 19.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 16.0

    static let tileSize: CGFloat = 24.0
    /// The row's padding inside its list.
    // spacing: 9 above and below, measured from Claude's Projects rows
    static let insets = EdgeInsets(top: 9.0, leading: Space.xxxl, bottom: 9.0, trailing: Space.xxxl)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xl) {
            IconlyIcon(icon, .row)
                .foregroundStyle(Color.textMuted)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .background(Color.surfaceTile, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                // Centered on the name's line, not on both lines.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: titleSize, design: .rounded))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                Text(subtitle)
                    .lineLimit(1)
                    .font(.system(size: subtitleSize, design: .rounded))
                    .foregroundStyle(Color.textMuted)
            }
            if isChecked {
                Spacer(minLength: 0)
                IconlyIcon(.check, .row)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                    .accessibilityLabel("Selected")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension View {
    /// A `TileRow`'s place in a plain list: no separator or background.
    func tileRowInList() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(TileRow.insets)
            .listRowBackground(Color.clear)
    }
}
