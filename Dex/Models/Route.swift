//
//  Route.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// A page pushed onto the main screen's stack, reached from another page
/// rather than the drawer: it gets the back button and edge swipe.
enum Route: Hashable {
    case folder(UUID)
    case chat(UUID)

    /// The folder's or chat's id.
    var id: UUID {
        switch self {
        case .folder(let id), .chat(let id): id
        }
    }

    /// The stack after asking for `route`. A page already in it, or the
    /// page at its root, is gone back to rather than pushed again: from a
    /// folder's chat, its folder chip returns to the folder.
    /// - Parameters:
    ///   - root: the drawer page under the stack.
    ///   - rootChatID: the chat on the root chat page, when that's the root.
    static func pushing(_ route: Route, onto routes: [Route], root: RootView.Page, rootChatID: UUID?) -> [Route] {
        switch (route, root) {
        case (.folder(let id), .folder(let rootID)) where id == rootID:
            return []
        case (.chat(let id), .chat) where id == rootChatID:
            return []
        default:
            break
        }
        if let index = routes.firstIndex(of: route) {
            return Array(routes[...index])
        }
        return routes + [route]
    }
}
