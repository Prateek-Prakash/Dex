//
//  FoldersView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftData
import SwiftUI

/// Folders, opened from the drawer, newest first. New Folder asks for a
/// name; a new folder opens straight away. A long press pins, renames or
/// deletes one. A folder opens pushed, with the back button and swipe.
struct FoldersView: View {
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    /// Pushes a page over this one.
    var push: (Route) -> Void = { _ in }

    @EnvironmentObject private var chatVM: ChatVM
    @Query(sort: Folder.newestFirst) private var folders: [Folder]
    @State private var isCreating = false
    /// The folder whose Rename or Delete dialog is up.
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?

    var body: some View {
        PageScaffold(title: "Folders", pillTitle: "New Folder", openDrawer: openDrawer, pillAction: {
            isCreating = true
        }) {
            List(folders) { folder in
                Button {
                    push(.folder(folder.id))
                } label: {
                    // Folders are only ever the owner's for now.
                    TileRow(icon: .folder, title: folder.name, subtitle: "Private")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ItemActions(isPinned: folder.pinnedAt != nil, pin: { chatVM.togglePin(folder) },
                                rename: { folderToRename = folder }, delete: { folderToDelete = folder })
                }
                .tileRowInList()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .folderActionAlerts(renaming: $folderToRename, deleting: $folderToDelete) { chatVM.delete($0) }
        // A new folder opens straight away.
        .folderCreationAlert(isPresented: $isCreating) { push(.folder($0.id)) }
    }
}

#Preview {
    FoldersView()
        .modelContainer(Storage.inMemory())
        .environmentObject(ChatVM())
}
