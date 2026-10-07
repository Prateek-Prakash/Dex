//
//  PageScaffold.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// A page: a centered title, an optional ⋯ menu, and a pill at the bottom
/// right, over the app background, around the page's content. Opened from
/// the drawer it has the drawer button and, unless a caller supplies one,
/// its own navigation stack. Pushed from another page it has neither: it
/// lives in that page's stack and gets the system back button and swipe,
/// like Settings' Models.
struct PageScaffold<Content: View, Actions: View>: View {
    let title: String
    let pillTitle: String
    var openDrawer: () -> Void = {}
    var pillAction: () -> Void = {}
    /// False when the caller wraps the page in its own stack (to push from it).
    var embedsStack: Bool = true
    /// False on a pushed page: the system back button takes its place.
    var showsDrawerButton: Bool = true
    @ViewBuilder var content: Content
    /// The ⋯ menu's items, top right; none when empty.
    @ViewBuilder var actions: Actions
    /// Read here, outside the toolbar, for `MoreMenuLabel`.
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if !embedsStack {
            page
        } else {
            NavigationStack {
                page
            }
            .tint(Color.primary)
        }
    }

    private var page: some View {
            // The background is the page's base, not a modifier on the
            // content: an empty page (EmptyView) draws nothing, and its
            // background, title and toolbar would vanish with it. Inside the
            // stack: the stack paints its own system background over
            // anything set behind it.
            ZStack {
                Color.pageBackground
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
                            .tint(Color.primary)
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
                    .padding(.horizontal, 16.0)
                    .padding(.bottom, 8.0)
                }
    }
}

extension PageScaffold where Actions == EmptyView {
    /// A page without a ⋯ menu.
    init(title: String, pillTitle: String, openDrawer: @escaping () -> Void = {}, pillAction: @escaping () -> Void = {},
         embedsStack: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title: title, pillTitle: pillTitle, openDrawer: openDrawer, pillAction: pillAction,
                  embedsStack: embedsStack, content: content, actions: { EmptyView() })
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
