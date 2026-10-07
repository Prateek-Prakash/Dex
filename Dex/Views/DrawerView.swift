//
//  DrawerView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The drawer behind the main screen: Folders, then pinned and recent
/// folders and chats once they're stored.
struct DrawerView: View {
    /// The main screen's uncovered width at the drawer's right; content
    /// stays clear of it.
    var sliver: CGFloat = 0
    /// The page the main screen shows; its row is highlighted.
    var page: RootView.Page = .chat
    /// Shows a page on the main screen.
    var select: (RootView.Page) -> Void = { _ in }
    /// Opens Settings.
    var openSettings: () -> Void = {}
    /// Mock until chat exists: closes the drawer onto the empty main screen.
    var newSession: () -> Void = {}
    
    /// The pinned or recent row that is highlighted; nil for the Folders
    /// row or a new session. A folder opens its own page; mock: every chat
    /// opens the one chat screen.
    @State private var selectedItem: DrawerItem?
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
                ForEach(DrawerItem.sections(pinned: DrawerItem.pinned, recent: DrawerItem.recent), id: \.title) { section in
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
            row(item.icon, item.title, isSelected: selectedItem == item) {
                selectedItem = item
                select(item.kind == .folder ? .folder(item.title) : .chat)
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
}
