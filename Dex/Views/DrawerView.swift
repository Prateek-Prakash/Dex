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
    /// Chats with a reply streaming here; their rows show a spinner, as do
    /// chats replying on another device (`replyingChatIDs`).
    var streamingChatIDs: Set<UUID> = []
    /// Shows a page on the main screen.
    var select: (RootView.Page) -> Void = { _ in }
    /// Opens a saved chat on the main screen.
    var openChat: (Chat) -> Void = { _ in }
    /// Renames a saved chat, once confirmed.
    var renameChat: (Chat, String) -> Void = { _, _ in }
    /// Deletes a saved chat, once confirmed.
    var deleteChat: (Chat) -> Void = { _ in }
    /// Pins or unpins a saved chat.
    var pinChat: (Chat) -> Void = { _ in }
    /// Pins or unpins a folder.
    var pinFolder: (Folder) -> Void = { _ in }
    /// Moves a chat into a folder, or out with nil.
    var moveChat: (Chat, Folder?) -> Void = { _, _ in }
    /// Deletes a folder and its chats, once confirmed.
    var deleteFolder: (Folder) -> Void = { _ in }
    /// Saves the pinned rows' new order after a drag, top first.
    var reorderPinned: ([DrawerItem]) -> Void = { _ in }
    /// Opens Settings.
    var openSettings: () -> Void = {}
    /// Starts an empty chat and closes the drawer onto it.
    var newSession: () -> Void = {}
    
    /// Every saved chat, latest first.
    @Query(sort: \Chat.lastMessageAt, order: .reverse) private var chats: [Chat]
    /// Every folder; the pinned ones show.
    @Query private var folders: [Folder]
    /// Replies stored streaming: here, on another device, or cut off.
    @Query(filter: Message.streaming) private var streamingMessages: [Message]
    /// Ticks every few seconds, so a reply whose device went quiet loses
    /// its spinner once it stops counting as live.
    @State private var now = Date()
    /// The chat whose Rename or Delete dialog is up.
    @State private var chatToRename: Chat?
    @State private var chatToDelete: Chat?
    /// The chat whose Organize sheet is up.
    @State private var chatToOrganize: Chat?
    /// The folder whose Rename or Delete dialog is up.
    @State private var folderToRename: Folder?
    @State private var folderToDelete: Folder?
    /// Section headers, a step above body; follow Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var headerTextSize: CGFloat = 17.0
    
    /// Where the "Dex" title starts, measured: the highlight's edges line up with it.
    @State private var titleLeading: CGFloat = 16.0
    /// Row text a little larger than body, like Claude's drawer; follows Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowTextSize: CGFloat = 21.0
    
    var body: some View {
        NavigationStack {
            List {
                row(.folder, "Folders", isSelected: page == .folders) {
                    select(.folders)
                }
                ForEach(DrawerItem.sections(pinned: DrawerItem.pinned(folders: folders, chats: chats),
                                            recent: DrawerItem.recent(chats)), id: \.title) { section in
                    self.section(section.title, section.items)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .safeAreaPadding(.trailing, sliver)
            .scrollContentBackground(.hidden)
            .background(Color.surfaceDrawer.ignoresSafeArea())
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
            .organizeSheet(for: $chatToOrganize, move: moveChat)
            .folderActionAlerts(renaming: $folderToRename, deleting: $folderToDelete, delete: deleteFolder)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        openSettings()
                    } label: {
                        IconlyIcon(.settings, .action)
                            .padding(Space.l)
                            .glassCircle()
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    PillButton(icon: .add, title: "New Session", action: newSession)
                }
                .padding(.horizontal, Space.xl)
                // The drawer is full width; keep clear of the main screen's sliver.
                .padding(.trailing, sliver)
            }
        }
        .tint(Color.ink)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = .now
            }
        }
    }

    /// Chats with a reply coming, here or on another device.
    private var replyingChatIDs: Set<UUID> {
        let elsewhere = streamingMessages
            .filter { $0.isLiveElsewhere(now: now) }
            .compactMap { $0.chat?.id }
        return streamingChatIDs.union(elsewhere)
    }

    /// The highlight's edges line up with the title and it is 48pt tall; a
    /// row's 24pt icon then has 12pt of room inside it on every side.
    static let highlightPadding: CGFloat = 12.0
    static let rowHeight: CGFloat = 48.0
    
    private var rowInsets: EdgeInsets {
        let inset = titleLeading + Self.highlightPadding
        return EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
    }
    
    /// A section header that scrolls with the list, then its rows. Pinned
    /// rows drag to reorder: a long press lifts one, and moving it leaves
    /// the menu for the drag.
    @ViewBuilder
    private func section(_ header: String, _ items: [DrawerItem]) -> some View {
        Text(header)
            .font(.system(size: headerTextSize, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, Space.xl)
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
            .listRowBackground(Color.clear)
        ForEach(items) { item in
            if item.kind == .folder, let folder = folders.first(where: { $0.id.uuidString == item.id }) {
                // Follows the page, so a rename or a delete anywhere can't
                // leave it stale.
                row(item.icon, item.title, isSelected: page == .folder(folder.id)) {
                    select(.folder(folder.id))
                }
                .contextMenu {
                    ItemActions(isPinned: folder.pinnedAt != nil, pin: { pinFolder(folder) },
                                rename: { folderToRename = folder }, delete: { folderToDelete = folder })
                }
            } else if let chat = chats.first(where: { $0.id.uuidString == item.id }) {
                row(item.icon, item.title, isSelected: page == .chat && chat.id == currentChatID,
                    isReplying: replyingChatIDs.contains(chat.id)) {
                    openChat(chat)
                }
                .contextMenu {
                    ItemActions(isPinned: chat.pinnedAt != nil, pin: { pinChat(chat) },
                                rename: { chatToRename = chat }, organize: { chatToOrganize = chat },
                                delete: { chatToDelete = chat })
                }
            }
        }
        .onMove(perform: header == DrawerItem.pinnedTitle ? { from, to in
            var moved = items
            moved.move(fromOffsets: from, toOffset: to)
            reorderPinned(moved)
        } : nil)
    }
    
    /// A drawer row: icon and title, highlighted while selected. The
    /// highlight is the row's own rounded background, not the list's row
    /// background, and the row's frame is exactly the highlight's: a lifted
    /// row (long press, drag to reorder) is then that rounded shape with its
    /// own color, never the system's black rectangle. Unselected, it's the
    /// drawer's color, so a lifted row reads clear.
    private func row(_ icon: Iconly, _ title: String, isSelected: Bool, isReplying: Bool = false,
                     action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
        return Button(action: action) {
            // spacing: icon to title, between the l and xl steps by design
            HStack(spacing: 14.0) {
                IconlyIcon(icon, .tile)
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: rowTextSize, design: .rounded))
                // A reply still coming, in this chat or off screen.
                if isReplying {
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Self.highlightPadding)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .background(isSelected ? Color.surfaceSelected : Color.surfaceDrawer, in: shape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape([.dragPreview, .contextMenuPreview], shape)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: titleLeading, bottom: 0, trailing: titleLeading))
        .listRowBackground(Color.clear)
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
