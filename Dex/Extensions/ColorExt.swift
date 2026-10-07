//
//  ColorExt.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

extension Color {
    /// The main screen's background, measured from Claude's chat screen.
    static let appBackground = Color(light: 0xF9F9F7, dark: 0x151515)

    /// A page's background (Folders, a folder), measured from Claude's
    /// Projects list: the chat screen's in light mode, darker in dark.
    static let pageBackground = Color(light: 0xF9F9F7, dark: 0x0B0B0B)
    
    /// The message box's model pill and microphone circle, measured from Claude's.
    static let composerChip = Color(light: 0xF0EFEC, dark: 0x434343)
    
    /// The context ring's fill and track, measured from Claude's.
    static let contextRing = Color(light: 0x3162B8, dark: 0x88C2FA)
    static let contextTrack = Color(light: 0xC8C8C6, dark: 0x686868)

    /// The Stop square on its chip, measured from Claude's (white in dark
    /// mode). A fixed color, not `.primary`, which the composer's glass
    /// blends toward gray.
    static let stopSquare = Color(light: 0x1F1F1E, dark: 0xF9F9F7)

    /// Inline code's chip and text in replies, measured from Claude's.
    static let inlineCodeFill = Color(light: 0xEDEDEC, dark: 0x262626)
    static let inlineCodeBorder = Color(light: 0xD3D3D1, dark: 0x3B3B3A)
    static let inlineCodeText = Color(light: 0x284E90, dark: 0x7AA5E6)

    /// The drawer's background, measured from Claude's.
    static let drawerBackground = Color(light: 0xF3F3F0, dark: 0x101010)

    /// What the main screen fades toward while the drawer is open, measured
    /// from Claude's: its own background in light mode, a lifted gray in dark.
    static let drawerFade = Color(light: 0xF9F9F7, dark: 0x191919)

    /// The selected drawer row's highlight, measured from Claude's.
    static let drawerSelection = Color(light: 0xE7E6E1, dark: 0x404040)
    
    /// The hairline around the main screen while the drawer is open.
    static let drawerBorder = Color(light: 0xCDCDCB, dark: 0x3A3A39)

    /// A Folders row's rounded icon tile and its subtitle (and glyph) gray,
    /// measured from Claude's Projects list.
    static let folderTile = Color(light: 0xEDEDEC, dark: 0x171717)
    static let folderSubtitle = Color(light: 0x888681, dark: 0x888781)

    /// Settings screens, measured from Claude's.
    static let settingsBackground = Color(light: 0xF9F9F7, dark: 0x151515)
    static let settingsCard = Color(light: 0xFFFFFF, dark: 0x20201F)
    static let settingsSeparator = Color(light: 0xE6E6E6, dark: 0x363635)
    
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
