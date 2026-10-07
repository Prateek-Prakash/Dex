//
//  FoldersView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// Folders, opened from the drawer. Empty until folders exist; New Folder
/// does nothing until their storage is designed.
struct FoldersView: View {
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    
    var body: some View {
        PageScaffold(title: "Folders", pillTitle: "New Folder", openDrawer: openDrawer) {
            // Mock: folders arrive with their storage.
        }
    }
}

#Preview {
    FoldersView()
}
