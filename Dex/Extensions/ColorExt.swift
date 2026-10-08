//
//  ColorExt.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// Every color in the app, named by role: `surface…` behind things,
/// `text…` for words, `ink` for solid marks, then borders, states and
/// accents. Light and dark values measured from Claude's iOS app unless
/// noted. Views use only these (test-enforced: `TokenTests`).
extension Color {
    // MARK: Surfaces

    /// The chat screen, sheets and Settings.
    static let surfaceBase = Color(light: 0xF9F9F7, dark: 0x151515)
    /// A page (Folders, a folder), from Claude's Projects list: the base in
    /// light mode, darker in dark.
    static let surfacePage = Color(light: 0xF9F9F7, dark: 0x0B0B0B)
    /// The drawer.
    static let surfaceDrawer = Color(light: 0xF3F3F0, dark: 0x101010)
    /// What the main screen fades toward while the drawer is open: the base
    /// in light mode, a lifted gray in dark.
    static let surfaceFade = Color(light: 0xF9F9F7, dark: 0x191919)
    /// Raised on the base: the composer's chips, message bubbles, code blocks.
    static let surfaceRaised = Color(light: 0xF0EFEC, dark: 0x434343)
    /// A Settings card.
    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x20201F)
    /// A row's rounded icon tile (Folders, Organize, a folder's chats).
    static let surfaceTile = Color(light: 0xEDEDEC, dark: 0x171717)
    /// Inline code's chip in replies.
    static let surfaceCode = Color(light: 0xEDEDEC, dark: 0x262626)
    /// The selected drawer row, and a lifted one.
    static let surfaceSelected = Color(light: 0xE7E6E1, dark: 0x404040)

    // MARK: Text and ink

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    /// A row's subtitle and its tile's glyph.
    static let textMuted = Color(light: 0x888681, dark: 0x888781)
    /// `<mark>`'s highlight behind text, a soft yellow in either appearance.
    static let textHighlight = Color(light: 0xFCEFA1, dark: 0x5C4E12)
    /// Solid marks: pill buttons, checks, the send circle, the toolbar tint.
    static let ink = Color.primary
    /// The Stop square: a fixed near-ink, not `.primary`, which the
    /// composer's glass blends toward gray.
    static let inkSoft = Color(light: 0x1F1F1E, dark: 0xF9F9F7)

    // MARK: Lines

    /// The hairline around the main screen while the drawer is open.
    static let border = Color(light: 0xCDCDCB, dark: 0x3A3A39)
    /// Inline code's chip outline.
    static let borderSubtle = Color(light: 0xD3D3D1, dark: 0x3B3B3A)
    /// Between Settings rows.
    static let separator = Color(light: 0xE6E6E6, dark: 0x363635)
    /// Under a raised mark (the drawer-open main screen).
    static let shadow = Color.black

    // MARK: States

    /// Delete, errors, a context ring that's nearly full.
    static let destructive = Color.red
    /// A context ring that's filling up.
    static let warning = Color.orange

    // MARK: Accents

    /// The context ring's fill.
    static let accent = Color(light: 0x3162B8, dark: 0x88C2FA)
    /// The context ring's track.
    static let track = Color(light: 0xC8C8C6, dark: 0x686868)
    /// Inline code's text in replies.
    static let accentText = Color(light: 0x284E90, dark: 0x7AA5E6)
    /// Links in replies.
    static let link = Color(uiColor: .link)
    /// The LiveMark's glow, in order: blue, purple, pink, orange.
    static let markGlow: [Color] = [
        Color(light: 0x3B82F6, dark: 0x60A5FA),
        Color(light: 0x8B5CF6, dark: 0xA78BFA),
        Color(light: 0xEC4899, dark: 0xF472B6),
        Color(light: 0xF97316, dark: 0xFB923C),
    ]
    /// Reply callouts, GitHub's alert colors.
    static let calloutNote = Color(light: 0x0969DA, dark: 0x4493F8)
    static let calloutTip = Color(light: 0x1A7F37, dark: 0x3FB950)
    static let calloutImportant = Color(light: 0x8250DF, dark: 0xAB7DF8)
    static let calloutWarning = Color(light: 0x9A6700, dark: 0xD29922)
    static let calloutCaution = Color(light: 0xCF222E, dark: 0xF85149)

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// The few colors drawn into UIKit images (menu icons, the ⋯ label).
extension UIColor {
    static let destructive = UIColor.systemRed
    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel

    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
