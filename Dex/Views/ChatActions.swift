//
//  ChatActions.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// Rename and Delete, with their icons: a saved chat's long-press and ⋯
/// menus, and a folder's ⋯ menu.
struct RenameDeleteActions: View {
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: rename) {
            Label { Text("Rename") } icon: { Iconly.edit.image(.menu) }
        }
        Button(role: .destructive, action: delete) {
            Label { Text("Delete") } icon: { Iconly.delete.image(.menu, tint: .systemRed) }
        }
    }
}

/// The ⋯ menu button's icon. The toolbar redraws a Menu's label as a
/// template in its own tint, ignoring the color set on it, so the glyph is
/// an image with the label color baked in (black in light mode, white in
/// dark), like Delete's red. Redrawn when the appearance changes, since a
/// baked-in color can't follow it on its own.
struct MoreMenuLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        Iconly.more.image(.action, tint: UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }
}

extension View {
    /// The Rename and Delete dialogs for whichever chat is set in
    /// `renaming` or `deleting`; each clears it when it closes.
    func chatActionAlerts(
        renaming: Binding<Chat?>,
        deleting: Binding<Chat?>,
        rename: @escaping (Chat, String) -> Void,
        delete: @escaping (Chat) -> Void
    ) -> some View {
        modifier(ChatActionAlerts(renaming: renaming, deleting: deleting, rename: rename, delete: delete))
    }
}

private struct ChatActionAlerts: ViewModifier {
    @Binding var renaming: Chat?
    @Binding var deleting: Chat?
    let rename: (Chat, String) -> Void
    let delete: (Chat) -> Void

    @State private var newTitle = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename Chat", isPresented: present($renaming), presenting: renaming) { chat in
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename(chat, newTitle) }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Starts from the current name, so a small fix is a small edit.
            .onChange(of: renaming) {
                if let chat = renaming { newTitle = chat.title }
            }
            .alert("Delete Chat", isPresented: present($deleting), presenting: deleting) { chat in
                Button("Delete", role: .destructive) { delete(chat) }
                Button("Cancel", role: .cancel) {}
            } message: { chat in
                Text(chat.title)
            }
    }

    private func present(_ chat: Binding<Chat?>) -> Binding<Bool> {
        Binding(get: { chat.wrappedValue != nil }, set: { if !$0 { chat.wrappedValue = nil } })
    }
}
