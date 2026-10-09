//
//  ChatActions.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// For a chat, Pin or Unpin; Rename and, for a chat, Organize; Delete:
/// with their icons, a divider between each group. A saved chat's
/// long-press and ⋯ menus, and a folder's (folders can't be pinned: Open
/// WebUI has no pinned folders). Pin shows the Light pin; Unpin, on a
/// pinned chat, the Bold.
struct ItemActions: View {
    var isPinned = false
    /// Pins or unpins a chat; nil for a folder.
    var pin: (() -> Void)?
    let rename: () -> Void
    /// Moves a chat into or out of a folder; nil for a folder.
    var organize: (() -> Void)?
    let delete: () -> Void

    var body: some View {
        if let pin {
            Button(action: pin) {
                Label {
                    Text(isPinned ? "Unpin" : "Pin")
                } icon: {
                    (isPinned ? Iconly.pinBold : Iconly.pin).image(.menu)
                }
            }
            Divider()
        }
        Button(action: rename) {
            Label { Text("Rename") } icon: { Iconly.edit.image(.menu) }
        }
        if let organize {
            Button(action: organize) {
                Label { Text("Organize") } icon: { Iconly.folder.image(.menu) }
            }
        }
        Divider()
        Button(role: .destructive, action: delete) {
            Label { Text("Delete") } icon: { Iconly.delete.image(.menu, tint: .destructive) }
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
        Iconly.more.image(.action, tint: UIColor.textPrimary.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
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

    @EnvironmentObject private var chatVM: ChatVM
    @State private var newName = ""
    /// The folder whose new name was just refused as taken, and that name.
    @State private var refused: (folder: Folder, name: String)?
    /// Why the server couldn't rename it.
    @State private var failure: String?
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
            .alert("Couldn't Rename Folder", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ), presenting: failure) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure)
            }
            .alert("Delete Folder", isPresented: present($deleting), presenting: deleting) { folder in
                Button("Delete", role: .destructive) { delete(folder) }
                Button("Cancel", role: .cancel) {}
            } message: { folder in
                Text("\(folder.name)\n\(Folder.chatCount(folder.chats.count))")
            }
    }

    /// Renamed on the server first, then here.
    private func rename(_ folder: Folder) {
        let name = newName
        Task {
            switch await chatVM.rename(folder, to: name) {
            case .taken(let taken): refused = (folder, taken)
            case .failed(let reason): failure = reason
            case .renamed, .unchanged: break
            }
        }
    }

    private func present(_ folder: Binding<Folder?>) -> Binding<Bool> {
        Binding(get: { folder.wrappedValue != nil }, set: { if !$0 { folder.wrappedValue = nil } })
    }
}

extension View {
    /// The Create Folder dialog, and its refusal of a name another folder
    /// has, which leads back to it with the typed name kept. `created` gets
    /// each new folder.
    func folderCreationAlert(isPresented: Binding<Bool>, created: @escaping (Folder) -> Void = { _ in }) -> some View {
        modifier(FolderCreationAlert(isPresented: isPresented, created: created))
    }
}

private struct FolderCreationAlert: ViewModifier {
    @Binding var isPresented: Bool
    let created: (Folder) -> Void

    @EnvironmentObject private var chatVM: ChatVM
    @State private var name = ""
    /// The name just refused as taken.
    @State private var takenName: String?
    /// Why the server couldn't make it.
    @State private var failure: String?
    /// Set when Create comes back after a refusal: keeps the typed name.
    @State private var keepsTypedName = false

    func body(content: Content) -> some View {
        content
            .alert("Create Folder", isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Create") { create() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Opens empty, unless coming back from a refusal.
            .onChange(of: isPresented) {
                guard isPresented else { return }
                if keepsTypedName {
                    keepsTypedName = false
                } else {
                    name = ""
                }
            }
            .alert("Folder Already Exists", isPresented: Binding(
                get: { takenName != nil },
                set: { if !$0 { takenName = nil } }
            ), presenting: takenName) { _ in
                Button("OK") {
                    keepsTypedName = true
                    isPresented = true
                }
            } message: { taken in
                Text(taken)
            }
            .alert("Couldn't Create Folder", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ), presenting: failure) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure)
            }
    }

    /// Made on the server first, so it has the server's id from the start.
    private func create() {
        Task {
            switch await chatVM.createFolder(named: name) {
            case .created(let folder):
                created(folder)
            case .taken(let taken):
                takenName = taken
            case .failed(let reason):
                failure = reason
            case .blank:
                break
            }
        }
    }
}

extension View {
    /// The Organize sheet for whichever chat is set in `organizing`; it
    /// clears it when the sheet closes.
    func organizeSheet(for organizing: Binding<Chat?>, move: @escaping (Chat, Folder?) -> Void) -> some View {
        sheet(item: organizing) { chat in
            // Claude's sheet: the chat screen's background, not a page's.
            OrganizeView(chat: chat, move: move)
                .presentationBackground(Color.surfaceBase)
        }
    }
}
