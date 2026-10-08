//
//  OrganizeView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftData
import SwiftUI

/// Moves a chat into a folder, or out of one, like Claude's Change Project
/// sheet: the Folders page's list, a check on the chat's folder. Tapping a
/// folder moves the chat there; tapping the checked one takes it out. Stays
/// open until closed or swiped away. + makes a folder, without moving the
/// chat into it.
struct OrganizeView: View {
    let chat: Chat
    let move: (Chat, Folder?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: Folder.newestFirst) private var folders: [Folder]
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List(folders) { folder in
                let isChecked = chat.folder === folder
                Button {
                    move(chat, isChecked ? nil : folder)
                } label: {
                    TileRow(icon: .folder, title: folder.name, subtitle: "Private", isChecked: isChecked)
                }
                .buttonStyle(.plain)
                .tileRowInList()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.surfaceBase.ignoresSafeArea())
            .sensoryFeedback(.selection, trigger: chat.folder?.id)
            .navigationTitle("Organize")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        IconlyIcon(.close, .action)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        IconlyIcon(.add, .action)
                    }
                    .accessibilityLabel("New Folder")
                }
            }
            .folderCreationAlert(isPresented: $isCreating)
        }
        .tint(Color.ink)
    }
}

#Preview {
    OrganizeView(chat: Chat(title: "Preview"), move: { _, _ in })
        .modelContainer(Storage.inMemory())
}
