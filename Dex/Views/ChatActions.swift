//
//  ChatActions.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// A saved chat's actions: the drawer row's long-press menu and the open
/// chat's ⋯ menu list the same ones.
struct ChatActions: View {
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
