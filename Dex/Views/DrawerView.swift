//
//  DrawerView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftData
import SwiftUI

/// The drawer behind the main screen: Folders, then pinned folders and
/// chats, then recent chats.
struct DrawerView: View {
    /// The main screen's uncovered width at the drawer's right; content
    /// stays clear of it.
    var sliver: CGFloat = 0
    /// The page the main screen shows; its row is highlighted.
    var page: RootView.Page = .chat
    /// The saved chat on the main screen; its row is highlighted.
    var currentChatID: UUID?
    /// Shows a page on the main screen.
    var select: (RootView.Page) -> Void = { _ in }
    /// Opens a saved chat on the main screen.
    var openChat: (Chat) -> Void = { _ in }
    /// Renames a saved chat, once confirmed.
    var renameChat: (Chat, String) -> Void = { _, _ in }
    /// Deletes a saved chat, once confirmed.
    var deleteChat: (Chat) -> Void = { _ in }
    /// Opens Settings.
    var openSettings: () -> Void = {}
    /// Starts an empty chat and closes the drawer onto it.
    var newSession: () -> Void = {}
    
    /// The pinned folder row that is highlighted; nil otherwise. A chat
    /// row's highlight follows `currentChatID` instead.
    @State private var selectedItem: DrawerItem?
    /// Every saved chat, latest first.
    @Query(sort: \Chat.lastMessageAt, order: .reverse) private var chats: [Chat]
    /// The chat whose Rename or Delete dialog is up.
    @State private var chatToRename: Chat?
    @State private var chatToDelete: Chat?
    /// Section headers, a step above body; follow Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var headerTextSize: CGFloat = 17.0
    
    /// Where the "Dex" title starts, measured: the highlight's edges line up with it.
    @State private var titleLeading: CGFloat = 16.0
    /// Row text a little larger than body, like Claude's drawer; follows Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowTextSize: CGFloat = 21.0
    
    var body: some View {
        NavigationStack {
            List {
                row(.folder, "Folders", isSelected: page == .folders && selectedItem == nil) {
                    selectedItem = nil
                    select(.folders)
                }
                ForEach(DrawerItem.sections(pinned: [], recent: chats.map(DrawerItem.init)), id: \.title) { section in
                    self.section(section.title, section.items)
                }
            }
            .listStyle(.plain)
            // A folder's New Session leaves the folder: drop its highlight.
            .onChange(of: page) {
                if page == .chat, selectedItem?.kind == .folder {
                    selectedItem = nil
                }
            }
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .safeAreaPadding(.trailing, sliver)
            .scrollContentBackground(.hidden)
            .background(Color.drawerBackground.ignoresSafeArea())
            // A fixed title, not the system one, which shrinks on scroll.
            // The list scrolls under the bar, which turns to glass.
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        title
                    }
                    // Plain text, not a glass button.
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        title
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .chatActionAlerts(renaming: $chatToRename, deleting: $chatToDelete, rename: renameChat, delete: deleteChat)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        openSettings()
                    } label: {
                        IconlyIcon(.settings, .action)
                            .padding(12.0)
                            .glassCircle()
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    PillButton(icon: .add, title: "New Session") {
                        selectedItem = nil
                        newSession()
                    }
                }
                .padding(.horizontal, 16.0)
                // The drawer is full width; keep clear of the main screen's sliver.
                .padding(.trailing, sliver)
            }
        }
        .tint(Color.primary)
    }

    /// The highlight's edges line up with the title and it is 48pt tall; a
    /// row's 24pt icon then has 12pt of room inside it on every side.
    static let highlightPadding: CGFloat = 12.0
    static let rowHeight: CGFloat = 48.0
    
    private var rowInsets: EdgeInsets {
        let inset = titleLeading + Self.highlightPadding
        return EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
    }
    
    /// A section header that scrolls with the list, then its chats.
    @ViewBuilder
    private func section(_ header: String, _ items: [DrawerItem]) -> some View {
        Text(header)
            .font(.system(size: headerTextSize, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 16.0)
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
            .listRowBackground(Color.clear)
        ForEach(items) { item in
            if item.kind == .folder {
                row(item.icon, item.title, isSelected: selectedItem == item) {
                    selectedItem = item
                    if let id = UUID(uuidString: item.id) { select(.folder(id)) }
                }
            } else if let chat = chats.first(where: { $0.id.uuidString == item.id }) {
                row(item.icon, item.title, isSelected: page == .chat && chat.id == currentChatID) {
                    selectedItem = nil
                    openChat(chat)
                }
                .contextMenu {
                    RenameDeleteActions(rename: { chatToRename = chat }, delete: { chatToDelete = chat })
                }
            }
        }
    }
    
    /// A drawer row: icon and title, highlighted while selected.
    private func row(_ icon: Iconly, _ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14.0) {
                IconlyIcon(icon, .tile)
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: rowTextSize, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(rowInsets)
        .listRowBackground(highlight(isSelected))
    }
    
    /// The selected row's rounded highlight, its edges in line with the title.
    @ViewBuilder
    private func highlight(_ isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                .fill(Color.drawerSelection)
                .padding(.horizontal, titleLeading)
        } else {
            Color.clear
        }
    }
    
    private var title: some View {
        // Monoton (bundled, OFL): neon-tube capitals, for the title only.
        Text("Dex")
            .font(Font.custom("Monoton-Regular", size: 28.0, relativeTo: .title))
            .fixedSize()
            // The drawer starts at the screen's left edge, so this is the
            // title's distance from the drawer's edge.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { titleLeading = $0 }
    }
}

#Preview {
    DrawerView()
        .modelContainer(Storage.inMemory())
}
