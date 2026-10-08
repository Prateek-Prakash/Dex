//
//  FolderView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftData
import SwiftUI

/// One folder, titled with its name, listing its chats, latest first.
/// Found by id, so a rename or sync shows at once and two folders can never
/// be confused. Opened from the drawer it has the drawer button; pushed
/// (from Folders, or a chat's folder chip), the back button. ⋯ pins,
/// renames or deletes it; deleted anywhere, it leaves. A chat opens pushed
/// over it; New Session pushes a new chat in it; a long press on a chat pins,
/// renames, organizes or deletes it.
struct FolderView: View {
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    /// Pushes a page over this one: one of its chats, or a new chat in it.
    var push: (Route) -> Void = { _ in }
    /// Pushed from Folders, not opened from the drawer.
    var isPushed = false
    /// Where a deleted folder leaves you: Folders, opened from the drawer;
    /// pushed, its place in the stack is taken out.
    var leave: () -> Void = {}

    @EnvironmentObject private var chatVM: ChatVM
    @Query private var folders: [Folder]
    /// Its chats, latest message first.
    @Query private var chats: [Chat]
    /// Set while its Rename or Delete dialog is up.
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    /// The chat whose Rename, Delete or Organize is up.
    @State private var chatToRename: Chat?
    @State private var chatToDelete: Chat?
    @State private var chatToOrganize: Chat?

    init(id: UUID, isPushed: Bool = false, openDrawer: @escaping () -> Void = {},
         push: @escaping (Route) -> Void = { _ in },
         leave: @escaping () -> Void = {}) {
        self.isPushed = isPushed
        self.openDrawer = openDrawer
        self.push = push
        self.leave = leave
        _folders = Query(filter: #Predicate<Folder> { $0.id == id })
        _chats = Query(filter: Chat.inFolder(id), sort: \Chat.lastMessageAt, order: .reverse)
    }

    private var folder: Folder? { folders.first }

    var body: some View {
        PageScaffold(title: folder?.name ?? "", pillTitle: "New Session", openDrawer: openDrawer,
                     pillAction: { if let folder { push(.newChat(folder.id)) } },
                     showsDrawerButton: !isPushed) {
            List(chats) { chat in
                Button {
                    push(.chat(chat.id))
                } label: {
                    // A placeholder until chats get a real subtitle.
                    TileRow(icon: .chat, title: chat.title, subtitle: "Subtitle")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ItemActions(isPinned: chat.pinnedAt != nil, pin: { chatVM.togglePin(chat) },
                                rename: { chatToRename = chat }, organize: { chatToOrganize = chat },
                                delete: { chatToDelete = chat })
                }
                .tileRowInList()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } actions: {
            if let folder {
                ItemActions(isPinned: folder.pinnedAt != nil, pin: { chatVM.togglePin(folder) },
                            rename: { folderToRename = folder }, delete: { folderToDelete = folder })
            }
        }
        .folderActionAlerts(renaming: $folderToRename, deleting: $folderToDelete) { folder in
            chatVM.delete(folder)
            leave()
        }
        .chatActionAlerts(renaming: $chatToRename, deleting: $chatToDelete,
                          rename: { chatVM.rename($0, to: $1) }, delete: { chatVM.delete($0) })
        .organizeSheet(for: $chatToOrganize) { chatVM.move($0, to: $1) }
        // Deleted from the drawer or another device: nothing left to show.
        .onChange(of: folder == nil) {
            if folder == nil { leave() }
        }
    }
}

#Preview {
    FolderView(id: UUID())
        .modelContainer(Storage.inMemory())
        .environmentObject(ChatVM())
}
