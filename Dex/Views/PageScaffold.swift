//
//  PageScaffold.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// A page the drawer opens: the drawer button, a centered title, and a pill
/// at the bottom right, over the app background. Content comes later.
struct PageScaffold: View {
    let title: String
    let pillTitle: String
    var openDrawer: () -> Void = {}
    var pillAction: () -> Void = {}
    
    var body: some View {
        NavigationStack {
            // Inside the stack: the stack paints its own system background
            // over anything set behind it.
            Color.appBackground
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            openDrawer()
                        } label: {
                            IconlyIcon(.menu, .action)
                        }
                    }
                }
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Spacer()
                        PillButton(icon: .add, title: pillTitle, action: pillAction)
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.bottom, 8.0)
                }
        }
        .tint(Color.primary)
    }
}

#Preview {
    PageScaffold(title: "Folders", pillTitle: "New Folder")
}
