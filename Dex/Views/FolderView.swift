//
//  FolderView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftData
import SwiftUI

/// One folder, opened from the drawer or the Folders page, titled with its
/// name. Found by id, so a rename or sync shows at once and two folders can
/// never be confused. Opened from the drawer it has the drawer button;
/// pushed from Folders, the system back button. ⋯ pins, renames or
/// deletes it; deleted anywhere, it leaves.
/// Will list the folder's chats.
struct FolderView: View {
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    var newSession: () -> Void = {}
    /// Pushed from Folders, not opened from the drawer.
    var isPushed = false
    /// Where a deleted folder leaves you.
    var leave: () -> Void = {}

    @EnvironmentObject private var chatVM: ChatVM
    @Query private var folders: [Folder]
    /// Set while its Rename or Delete dialog is up.
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?

    init(id: UUID, isPushed: Bool = false, openDrawer: @escaping () -> Void = {},
         newSession: @escaping () -> Void = {}, leave: @escaping () -> Void = {}) {
        self.isPushed = isPushed
        self.openDrawer = openDrawer
        self.newSession = newSession
        self.leave = leave
        _folders = Query(filter: #Predicate<Folder> { $0.id == id })
    }

    private var folder: Folder? { folders.first }

    var body: some View {
        PageScaffold(title: folder?.name ?? "", pillTitle: "New Session", openDrawer: openDrawer,
                     pillAction: newSession, embedsStack: !isPushed, showsDrawerButton: !isPushed) {
            EmptyView()
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
