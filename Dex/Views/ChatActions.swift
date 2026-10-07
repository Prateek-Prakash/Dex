//
//  ChatActions.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// Pin or Unpin, Rename and Delete, with their icons and a divider after
/// each of the first two: a saved chat's long-press and ⋯ menus, and a
/// folder's. Pin shows the Light pin; Unpin, on a pinned item, the Bold.
struct ItemActions: View {
    let isPinned: Bool
    let pin: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: pin) {
            Label {
                Text(isPinned ? "Unpin" : "Pin")
            } icon: {
                (isPinned ? Iconly.pinBold : Iconly.pin).image(.menu)
            }
        }
        Divider()
        Button(action: rename) {
            Label { Text("Rename") } icon: { Iconly.edit.image(.menu) }
        }
        Divider()
        Button(role: .destructive, action: delete) {
            Label { Text("Delete") } icon: { Iconly.delete.image(.menu, tint: .systemRed) }
        }
    }
}

/// The ⋯ menu button's icon, the label color drawn into its pixels:
/// black in light mode, white in dark, matching the back and drawer
/// buttons. A template label comes out a dim, opposite-mode gray in the
/// toolbar, and the scheme is read by the caller, outside the toolbar.
struct MoreMenuLabel: View {
    /// The page's color scheme, read outside the toolbar.
    let colorScheme: ColorScheme

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

extension View {
    /// The Rename and Delete dialogs for whichever folder is set in
    /// `renaming` or `deleting`; each clears it when it closes. A name
    /// another folder has is refused, then Rename comes back to fix it.
    func folderActionAlerts(
        renaming: Binding<Folder?>,
        deleting: Binding<Folder?>,
        delete: @escaping (Folder) -> Void
    ) -> some View {
        modifier(FolderActionAlerts(renaming: renaming, deleting: deleting, delete: delete))
    }
}

private struct FolderActionAlerts: ViewModifier {
    @Binding var renaming: Folder?
    @Binding var deleting: Folder?
    let delete: (Folder) -> Void

    @Environment(\.modelContext) private var context
    @State private var newName = ""
    /// The folder whose new name was just refused as taken, and that name.
    @State private var refused: (folder: Folder, name: String)?
    /// Set when Rename comes back after a refusal: keeps the typed name.
    @State private var keepsTypedName = false

    func body(content: Content) -> some View {
        content
            .alert("Rename Folder", isPresented: present($renaming), presenting: renaming) { folder in
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename(folder) }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Starts from the current name, unless coming back from a
            // refusal with the typed name still there to fix.
            .onChange(of: renaming) {
                guard let folder = renaming else { return }
                if keepsTypedName {
                    keepsTypedName = false
                } else {
                    newName = folder.name
                }
            }
            .alert("Folder Already Exists", isPresented: Binding(
                get: { refused != nil },
                set: { if !$0 { refused = nil } }
            ), presenting: refused) { refused in
                // The presented value, not the state, which the alert may
                // have cleared by now.
                Button("OK") {
                    keepsTypedName = true
                    renaming = refused.folder
                }
            } message: { refused in
                Text(refused.name)
            }
            .alert("Delete Folder", isPresented: present($deleting), presenting: deleting) { folder in
                Button("Delete", role: .destructive) { delete(folder) }
                Button("Cancel", role: .cancel) {}
            } message: { folder in
                Text("\(folder.name)\n\(Folder.chatCount(folder.chats?.count ?? 0))")
            }
    }

    private func rename(_ folder: Folder) {
        if case .taken(let taken) = Folder.rename(folder, to: newName, in: context) {
            refused = (folder, taken)
        }
    }

    private func present(_ folder: Binding<Folder?>) -> Binding<Bool> {
        Binding(get: { folder.wrappedValue != nil }, set: { if !$0 { folder.wrappedValue = nil } })
    }
}
