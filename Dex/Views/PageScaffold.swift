//
//  PageScaffold.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// A page: a centered title, an optional ⋯ menu, and a pill at the bottom
/// right, over the app background, around the page's content. It lives in
/// the main screen's stack: opened from the drawer it has the drawer
/// button; pushed from another page, the system back button and swipe.
struct PageScaffold<Content: View, Actions: View>: View {
    let title: String
    let pillTitle: String
    var openDrawer: () -> Void = {}
    var pillAction: () -> Void = {}
    /// False on a pushed page: the system back button takes its place.
    var showsDrawerButton: Bool = true
    @ViewBuilder var content: Content
    /// The ⋯ menu's items, top right; none when empty.
    @ViewBuilder var actions: Actions
    /// Read here, outside the toolbar, for `MoreMenuLabel`.
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
            // The background is the page's base, not a modifier on the
            // content: an empty page (EmptyView) draws nothing, and its
            // background, title and toolbar would vanish with it. Inside the
            // stack: the stack paints its own system background over
            // anything set behind it.
            ZStack {
                Color.surfacePage
                    .ignoresSafeArea()
                content
            }
                .toolbar {
                    if showsDrawerButton {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                openDrawer()
                            } label: {
                                IconlyIcon(.menu, .action)
                            }
                        }
                    }
                    if Actions.self != EmptyView.self {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                actions
                            } label: {
                                MoreMenuLabel(colorScheme: colorScheme)
                            }
                            .tint(Color.ink)
                            .accessibilityLabel("Options")
                        }
                    }
                }
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Spacer()
                        PillButton(icon: .add, title: pillTitle, action: pillAction)
                    }
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.m)
                }
    }
}

extension PageScaffold where Actions == EmptyView {
    /// A page without a ⋯ menu.
    init(title: String, pillTitle: String, openDrawer: @escaping () -> Void = {}, pillAction: @escaping () -> Void = {},
         showsDrawerButton: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title: title, pillTitle: pillTitle, openDrawer: openDrawer, pillAction: pillAction,
                  showsDrawerButton: showsDrawerButton, content: content, actions: { EmptyView() })
    }
}

extension PageScaffold where Content == EmptyView, Actions == EmptyView {
    /// A page with nothing in it yet.
    init(title: String, pillTitle: String, openDrawer: @escaping () -> Void = {}, pillAction: @escaping () -> Void = {}) {
        self.init(title: title, pillTitle: pillTitle, openDrawer: openDrawer, pillAction: pillAction) { EmptyView() }
    }
}

#Preview {
    PageScaffold(title: "Folders", pillTitle: "New Folder")
}
