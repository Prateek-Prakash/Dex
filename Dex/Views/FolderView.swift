//
//  FolderView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// One folder, opened from the drawer, titled with its name. Will list the
/// folder's chats; New Session starts a chat (a mock until chat exists).
struct FolderView: View {
    let name: String
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    var newSession: () -> Void = {}
    
    var body: some View {
        PageScaffold(title: name, pillTitle: "New Session", openDrawer: openDrawer, pillAction: newSession)
    }
}

#Preview {
    FolderView(name: "Home Lab")
}
