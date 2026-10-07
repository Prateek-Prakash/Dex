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
    
    /// The message box's model pill and microphone circle, measured from Claude's.
    static let composerChip = Color(light: 0xF0EFEC, dark: 0x434343)
    
    /// The context ring's fill and track, measured from Claude's.
    static let contextRing = Color(light: 0x3162B8, dark: 0x88C2FA)
    static let contextTrack = Color(light: 0xC8C8C6, dark: 0x686868)

    /// The drawer's background, measured from Claude's.
    static let drawerBackground = Color(light: 0xF3F3F0, dark: 0x101010)

    /// What the main screen fades toward while the drawer is open, measured
    /// from Claude's: its own background in light mode, a lifted gray in dark.
    static let drawerFade = Color(light: 0xF9F9F7, dark: 0x191919)

    /// The selected drawer row's highlight, measured from Claude's.
    static let drawerSelection = Color(light: 0xE7E6E1, dark: 0x404040)
    
    /// The hairline around the main screen while the drawer is open.
    static let drawerBorder = Color(light: 0xCDCDCB, dark: 0x3A3A39)

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
