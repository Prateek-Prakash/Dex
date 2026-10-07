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
/// deletes one. A folder opens pushed onto this
/// page's stack, with the system back button and swipe.
struct FoldersView: View {
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    /// The pill on a folder's page.
    var newSession: () -> Void = {}
    /// Tells the root whether a folder is pushed: its edge swipe is then
    /// Back, never the drawer.
    var isShowingFolder: (Bool) -> Void = { _ in }

    /// The pushed folders' ids; at most one for now.
    @State private var path: [UUID] = []

    @EnvironmentObject private var chatVM: ChatVM
    @Environment(\.modelContext) private var context
    @Query(sort: Folder.newestFirst) private var folders: [Folder]
    @State private var isCreating = false
    @State private var name = ""
    /// The name just refused as taken; its alert leads back to Create Folder.
    @State private var takenName: String?
    /// The folder whose Rename or Delete dialog is up.
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    /// Sizes measured from Claude's Projects list; follow Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 19.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 16.0

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationDestination(for: UUID.self) { id in
                    FolderView(id: id, isPushed: true, newSession: newSession, leave: { path.removeAll() })
                }
        }
        .tint(Color.primary)
        .onChange(of: path) { isShowingFolder(!path.isEmpty) }
    }

    private var list: some View {
        PageScaffold(title: "Folders", pillTitle: "New Folder", openDrawer: openDrawer, pillAction: {
            name = ""
            isCreating = true
        }, embedsStack: false) {
            List(folders) { folder in
                Button {
                    path.append(folder.id)
                } label: {
                    row(folder)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ItemActions(isPinned: folder.pinnedAt != nil, pin: { chatVM.togglePin(folder) },
                                rename: { folderToRename = folder }, delete: { folderToDelete = folder })
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 9.0, leading: 24.0, bottom: 9.0, trailing: 24.0))
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .folderActionAlerts(renaming: $folderToRename, deleting: $folderToDelete) { chatVM.delete($0) }
        .alert("Create Folder", isPresented: $isCreating) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") { create() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Folder Already Exists", isPresented: Binding(
            get: { takenName != nil },
            set: { if !$0 { takenName = nil } }
        ), presenting: takenName) { _ in
            // Back to Create Folder, the typed name still there to fix.
            Button("OK") { isCreating = true }
        } message: { taken in
            Text(taken)
        }
    }

    /// Like Claude's Projects rows: a rounded tile with the folder glyph,
    /// level with the name, and a subtitle under the name.
    private func row(_ folder: Folder) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16.0) {
            IconlyIcon(.folder, .row)
                .foregroundStyle(Color.folderSubtitle)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .background(Color.folderTile, in: RoundedRectangle(cornerRadius: 7.0, style: .continuous))
                // Centered on the name's line, not on both lines.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            VStack(alignment: .leading, spacing: 2.0) {
                Text(folder.name)
                    .lineLimit(1)
                    .font(.system(size: titleSize, design: .rounded))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                // Folders are only ever the owner's for now.
                Text("Private")
                    .font(.system(size: subtitleSize, design: .rounded))
                    .foregroundStyle(Color.folderSubtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    static let tileSize: CGFloat = 24.0

    private func create() {
        switch Folder.create(named: name, in: context) {
        case .created(let folder):
            path.append(folder.id)
        case .taken(let taken):
            takenName = taken
        case .blank:
            break
        }
    }
}

#Preview {
    FoldersView()
        .modelContainer(Storage.inMemory())
        .environmentObject(ChatVM())
}
