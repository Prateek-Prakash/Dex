//
//  Layout.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import CoreGraphics

/// The spacing scale: padding, stack spacing and insets. Views use only
/// these; a one-off measured value (a Claude match) stays as written with a
/// `// spacing: <reason>` comment on the line above (test-enforced:
/// `TokenTests`). Sized by name, so the scale can change in one place.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}

/// Corner radii, by the shape they round: "make every block rounder" is
/// one change here (test-enforced: `TokenTests`).
enum Radius {
    /// The composer's Stop square.
    static let stopSquare: CGFloat = 3
    /// Inline code's chip in replies.
    static let inlineCode: CGFloat = 5
    /// A row's icon tile (Folders, Organize, a folder's chats).
    static let tile: CGFloat = 7
    /// Blocks: the drawer row highlight, code blocks, tables, callouts.
    static let block: CGFloat = 12
    /// A message bubble.
    static let bubble: CGFloat = 20
    /// The composer.
    static let composer: CGFloat = 28
}
