//
//  ViewExt.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

extension View {
    /// A round Liquid Glass button surface, or a material one before iOS 26.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
    }
    
    /// A settings list's own background, in place of the system one.
    func settingsList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.settingsBackground.ignoresSafeArea())
    }
    
    /// Rows on settings cards: card fill and divider color.
    func settingsRows(background: Color = .settingsCard) -> some View {
        listRowBackground(background)
            .listRowSeparatorTint(.settingsSeparator)
    }
    
    /// A rounded Liquid Glass surface, or a material one before iOS 26.
    @ViewBuilder
    func glassRoundedRect(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
