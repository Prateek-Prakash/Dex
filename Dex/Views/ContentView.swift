//
//  ContentView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftData
import SwiftUI

/// The chat screen. As the drawer's chat page it shows whatever chat is on
/// screen and has the drawer button; pushed (from a folder's page) it opens
/// its own chat and has the back button.
struct ContentView: View {
    @EnvironmentObject var serverVM: ServerVM
    @EnvironmentObject var chatVM: ChatVM
    /// Read here, outside the toolbar, for `MoreMenuLabel`.
    @Environment(\.colorScheme) private var colorScheme
    
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    /// Pushes a page over this one: the chat's folder, from its chip.
    var push: (Route) -> Void = { _ in }
    /// The chat this screen was pushed for; nil on the drawer's chat page.
    var pushedChat: Chat?
    /// Pushed for a new chat in this folder (a folder's New Session).
    var newChatFolder: Folder?
    /// That new chat, once its first message saves it.
    @State private var startedChat: Chat?
    @State private var hasAppeared = false

    private var isPushed: Bool { pushedChat != nil || newChatFolder != nil }
    
    @FocusState private var isComposerFocused: Bool
    /// The chat whose Rename or Delete dialog is up.
    @State private var chatToRename: Chat?
    @State private var chatToDelete: Chat?
    @State private var chatToOrganize: Chat?
    
    var body: some View {
        Group {
            if chatVM.messages.isEmpty {
                emptyChat
            } else {
                ChatTranscriptView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if let id = chatVM.chat?.id {
                ChatSync(chatID: id)
                    .id(id)
            }
        }
        // Inside the stack: the stack paints its own system background
        // over anything set behind it.
        .background(Color.surfaceBase.ignoresSafeArea())
        .toolbar {
            // Pushed, the system back button takes its place.
            if !isPushed {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        openDrawer()
                    } label: {
                        IconlyIcon(.menu, .action)
                    }
                }
            }
            // Like Claude: the chat's folder, in its own glass beside the
            // drawer or back button; tapping it opens the folder's page,
            // going back to it if that's where the chat came from.
            // A new chat started in a folder shows it before its first
            // message; an incognito one never joins it.
            if let folder = chatVM.chat?.folder ?? (chatVM.isIncognito ? nil : chatVM.newChatFolder) {
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        push(.folder(folder.id))
                    } label: {
                        HStack(spacing: Space.s) {
                            IconlyIcon(.folder, .chip)
                            Text(folder.name)
                                .lineLimit(1)
                                .fontDesign(.rounded)
                        }
                        .padding(.horizontal, Space.xs)
                    }
                    .accessibilityLabel("Folder \(folder.name)")
                }
            }
            // Once a chat starts, the context ring shows top right, beside
            // the close button in an incognito chat.
            if !chatVM.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    // Empty until the first reply reports its size.
                    ContextMeter(used: chatVM.contextUsed ?? 0, total: WebUIReplyRequest.contextLength)
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
            }
            // Like Claude: a chat turns incognito before it starts, not
            // after. A started incognito chat gets a close button instead,
            // back to a new, ordinary chat; a started saved chat gets the
            // ⋯ menu, the drawer's long-press actions.
            if chatVM.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    incognitoButton
                }
            } else if chatVM.isIncognito {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            // On a folder's New Session, still in the folder.
                            chatVM.reset(into: newChatFolder)
                        }
                    } label: {
                        IconlyIcon(.close, .action)
                    }
                    .accessibilityLabel("Close Incognito Chat")
                }
            } else if let chat = chatVM.chat {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ItemActions(isPinned: chat.pinnedAt != nil, pin: { chatVM.togglePin(chat) },
                                    rename: { chatToRename = chat }, organize: { chatToOrganize = chat },
                                    delete: { chatToDelete = chat })
                    } label: {
                        MoreMenuLabel(colorScheme: colorScheme)
                    }
                    .tint(Color.ink)
                    .accessibilityLabel("Chat Options")
                }
            }
        }
        .chatActionAlerts(
            renaming: $chatToRename,
            deleting: $chatToDelete,
            rename: { chatVM.rename($0, to: $1) },
            delete: { chatVM.delete($0) }
        )
        .organizeSheet(for: $chatToOrganize) { chatVM.move($0, to: $1) }
        .navigationTitle(chatVM.isIncognito ? "Incognito" : "")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            ComposerView(isFocused: $isComposerFocused)
        }
        // Pushed: its own chat on screen each time it shows, coming back
        // from a page pushed over it included.
        .onAppear {
            if let pushedChat, !pushedChat.isDeleted { chatVM.open(pushedChat) }
            if let newChatFolder { showNewChat(in: newChatFolder) }
        }
        // A pushed new chat's first message saves it: that chat is now this
        // screen's.
        .onChange(of: chatVM.chat) {
            guard let newChatFolder else { return }
            if startedChat == nil, let chat = chatVM.chat, chat.folder === newChatFolder {
                startedChat = chat
            } else if let startedChat, startedChat.isDeleted || startedChat.modelContext == nil {
                // Deleted, here or elsewhere: a fresh new chat in the folder.
                self.startedChat = nil
                if chatVM.chat == nil { chatVM.reset(into: newChatFolder) }
            }
        }
    }
    
    /// A pushed new chat on screen: started fresh the first time, then, on
    /// coming back from a page pushed over it, the chat it became, or a
    /// fresh one again if it never got a message.
    private func showNewChat(in folder: Folder) {
        if !hasAppeared {
            hasAppeared = true
            chatVM.reset(into: folder)
        } else if let startedChat, !startedChat.isDeleted {
            chatVM.open(startedChat)
        } else if chatVM.chat != nil || chatVM.newChatFolder !== folder {
            chatVM.reset(into: folder)
        }
    }

    /// Turns a new chat incognito, or back.
    private var incognitoButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                chatVM.isIncognito.toggle()
            }
        } label: {
            // On: inverted icon in a filled circle, like Claude.
            // The circle is a backdrop, not padding, so the button
            // stays the menu button's size and its glass stays round.
            IconlyIcon(.incognito, .action)
                .foregroundStyle(chatVM.isIncognito ? Color.surfaceBase : Color.textPrimary)
                .background {
                    Circle()
                        .fill(chatVM.isIncognito ? Color.ink : Color.clear)
                        .frame(width: 36.0, height: 36.0)
                }
        }
        .sensoryFeedback(.selection, trigger: chatVM.isIncognito)
    }

    /// A new chat: the mark and a greeting, or in incognito what that means.
    private var emptyChat: some View {
        // Rechecked each minute, so the greeting turns over on time.
        TimelineView(.everyMinute) { context in
            VStack(spacing: Space.xxl) {
                LiveMark(isAlive: serverVM.isReachable)
                // A quiet caption under the mark, not a second headline.
                Text(chatVM.isIncognito ? "THIS CHAT WON'T BE SAVED" : Greeting.text(for: context.date))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .tracking(3.0)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tap anywhere above the message box to put the keyboard away.
        .contentShape(Rectangle())
        .onTapGesture {
            isComposerFocused = false
        }
    }
}

/// A chat pushed by id, found in the store. Deleted, here or on another
/// device, its place in the stack is taken out (`leave`).
struct PushedChatView: View {
    var push: (Route) -> Void = { _ in }
    var leave: () -> Void = {}
    @Query private var chats: [Chat]

    init(id: String, push: @escaping (Route) -> Void, leave: @escaping () -> Void) {
        self.push = push
        self.leave = leave
        _chats = Query(filter: #Predicate<Chat> { $0.id == id })
    }

    var body: some View {
        ZStack {
            Color.surfaceBase.ignoresSafeArea()
            if let chat = chats.first {
                ContentView(push: push, pushedChat: chat)
            }
        }
        .onChange(of: chats.isEmpty) {
            if chats.isEmpty { leave() }
        }
    }
}

/// A folder's New Session, pushed: a new chat in the folder found by id.
/// The folder deleted, its place in the stack is taken out (`leave`).
struct PushedNewChatView: View {
    var push: (Route) -> Void = { _ in }
    var leave: () -> Void = {}
    @Query private var folders: [Folder]

    init(folderID: String, push: @escaping (Route) -> Void, leave: @escaping () -> Void) {
        self.push = push
        self.leave = leave
        _folders = Query(filter: #Predicate<Folder> { $0.id == folderID })
    }

    var body: some View {
        ZStack {
            Color.surfaceBase.ignoresSafeArea()
            if let folder = folders.first {
                ContentView(push: push, newChatFolder: folder)
            }
        }
        .onChange(of: folders.isEmpty) {
            if folders.isEmpty { leave() }
        }
    }
}

/// Keeps the open chat in step with the store. Its queries refire after
/// any change to the chat's messages; a chat deleted from the store leaves
/// the screen.
private struct ChatSync: View {
    let chatID: String
    @EnvironmentObject private var chatVM: ChatVM
    @Query private var chats: [Chat]
    @Query private var messages: [Message]

    init(chatID: String) {
        self.chatID = chatID
        _chats = Query(filter: #Predicate<Chat> { $0.id == chatID })
        _messages = Query(filter: Message.inChat(chatID))
    }

    var body: some View {
        Color.clear
            .onChange(of: messages.map { ChatMessage($0) }) {
                chatVM.refresh()
            }
            .onChange(of: chats.isEmpty) {
                if chats.isEmpty, chatVM.chat?.id == chatID { chatVM.reset() }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerVM())
        .environmentObject(ModelsVM())
        .environmentObject(ChatVM())
}
