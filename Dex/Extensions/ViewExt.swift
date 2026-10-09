//
//  ViewExt.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

extension View {
    /// The toolbar's glass, with its hairline, where content scrolls under
    /// it, like the drawer's; asked for outright, as the chat list stopped
    /// getting it by default.
    @ViewBuilder
    func toolbarGlassEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }

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
            .background(Color.surfaceBase.ignoresSafeArea())
            // Claude's spacing: cards 16pt apart, and 16pt below the bar,
            // not the system's 35pt (room for section headers Dex doesn't have).
            .listSectionSpacing(Space.xl)
            .contentMargins(.top, Space.xl, for: .scrollContent)
    }
    
    /// Rows on settings cards: card fill and divider color.
    func settingsRows(background: Color = .surfaceCard) -> some View {
        listRowBackground(background)
            .listRowSeparatorTint(.separator)
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
