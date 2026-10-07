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
/// pushed from Folders, the system back button. ⋯ renames or deletes it.
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
    @Environment(\.modelContext) private var context
    @Query private var folders: [Folder]
    @State private var isRenaming = false
    @State private var newName = ""
    /// The name just refused as taken; its alert leads back to Rename Folder.
    @State private var takenName: String?
    @State private var isDeleting = false

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
            RenameDeleteActions(rename: {
                newName = folder?.name ?? ""
                isRenaming = true
            }, delete: {
                isDeleting = true
            })
        }
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Folder Already Exists", isPresented: Binding(
            get: { takenName != nil },
            set: { if !$0 { takenName = nil } }
        ), presenting: takenName) { _ in
            // Back to Rename Folder, the typed name still there to fix.
            Button("OK") { isRenaming = true }
        } message: { taken in
            Text(taken)
        }
        .alert("Delete Folder", isPresented: $isDeleting, presenting: folder) { folder in
            Button("Delete", role: .destructive) {
                chatVM.delete(folder)
                leave()
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("\(folder.name)\n\(Folder.chatCount(folder.chats?.count ?? 0))")
        }
    }

    private func rename() {
        guard let folder else { return }
        if case .taken(let taken) = Folder.rename(folder, to: newName, in: context) {
            takenName = taken
        }
    }
}

#Preview {
    FolderView(id: UUID())
        .modelContainer(Storage.inMemory())
        .environmentObject(ChatVM())
}
