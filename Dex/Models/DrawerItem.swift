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
    
    /// The drawer's sections in order, leaving out any with no items.
    static func sections(pinned: [DrawerItem], recent: [DrawerItem]) -> [(title: String, items: [DrawerItem])] {
        [("Pinned", pinned), ("Recent", recent)].filter { !$0.items.isEmpty }
    }
}
