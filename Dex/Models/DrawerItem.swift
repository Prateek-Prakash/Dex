//
//  DrawerItem.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation

/// A pinned or recent row in the drawer.
struct DrawerItem: Identifiable, Hashable {
    enum Kind {
        /// A folder; only pinned.
        case folder
        /// A chat inside a folder.
        case folderChat
        /// A chat on its own.
        case chat
    }
    
    /// Its own identity, not the title: two chats can share a name.
    let id: String
    let title: String
    let kind: Kind
    
    init(id: String = UUID().uuidString, title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
    
    /// Folders, and the chats in them, show a folder; single chats a bubble.
    var icon: Iconly {
        kind == .chat ? .chat : .folder
    }
    
    /// A saved chat's row, keyed by the chat's id.
    init(_ chat: Chat) {
        self.init(id: chat.id.uuidString, title: chat.title, kind: chat.folder == nil ? .chat : .folderChat)
    }
    
    /// A folder's row, keyed by the folder's id.
    init(_ folder: Folder) {
        self.init(id: folder.id.uuidString, title: folder.name, kind: .folder)
    }

    /// Pinned folders and chats together, the latest pinned first.
    static func pinned(folders: [Folder], chats: [Chat]) -> [DrawerItem] {
        let rows = folders.compactMap { folder in folder.pinnedAt.map { ($0, DrawerItem(folder)) } }
            + chats.compactMap { chat in chat.pinnedAt.map { ($0, DrawerItem(chat)) } }
        return rows.sorted { $0.0 > $1.0 }.map(\.1)
    }

    /// The chats not pinned, in the order given (latest message first).
    static func recent(_ chats: [Chat]) -> [DrawerItem] {
        chats.filter { $0.pinnedAt == nil }.map(DrawerItem.init)
    }

    /// The pinned section's title; its rows drag to reorder.
    static let pinnedTitle = "Pinned"

    /// The drawer's sections in order, leaving out any with no items.
    static func sections(pinned: [DrawerItem], recent: [DrawerItem]) -> [(title: String, items: [DrawerItem])] {
        [(pinnedTitle, pinned), ("Recent", recent)].filter { !$0.items.isEmpty }
    }
}
