//
//  ContentView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var globalVM: GlobalVM
    @EnvironmentObject var chatVM: ChatVM
    /// Read here, outside the toolbar, for `MoreMenuLabel`.
    @Environment(\.colorScheme) private var colorScheme
    
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    
    @FocusState private var isComposerFocused: Bool
    /// The chat whose Rename or Delete dialog is up.
    @State private var chatToRename: Chat?
    @State private var chatToDelete: Chat?
    
    var body: some View {
        NavigationStack {
            Group {
                if chatVM.messages.isEmpty {
                    emptyChat
                } else {
                    ChatTranscriptView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Inside the stack: the stack paints its own system background
            // over anything set behind it.
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        openDrawer()
                    } label: {
                        IconlyIcon(.menu, .action)
                    }
                }
                // Once a chat starts, the context ring shows top right, beside
                // the close button in an incognito chat.
                if !chatVM.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Empty until the first reply reports its size.
                        ContextMeter(used: chatVM.contextUsed ?? 0, total: OllamaChatRequest.contextLength)
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
                                chatVM.reset()
                            }
                        } label: {
                            IconlyIcon(.close, .action)
                        }
                        .accessibilityLabel("Close Incognito Chat")
                    }
                } else if let chat = chatVM.chat {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            RenameDeleteActions(rename: { chatToRename = chat }, delete: { chatToDelete = chat })
                        } label: {
                            MoreMenuLabel(colorScheme: colorScheme)
                        }
                        .tint(Color.primary)
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
            .navigationTitle(chatVM.isIncognito ? "Incognito" : "")
            .toolbarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ComposerView(isFocused: $isComposerFocused)
            }
        }
        .tint(Color.primary)
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
                .foregroundStyle(chatVM.isIncognito ? Color.appBackground : Color.primary)
                .background {
                    Circle()
                        .fill(chatVM.isIncognito ? Color.primary : Color.clear)
                        .frame(width: 36.0, height: 36.0)
                }
        }
        .sensoryFeedback(.selection, trigger: chatVM.isIncognito)
    }

    /// A new chat: the mark and a greeting, or in incognito what that means.
    private var emptyChat: some View {
        // Rechecked each minute, so the greeting turns over on time.
        TimelineView(.everyMinute) { context in
            VStack(spacing: 20.0) {
                LiveMark(isAlive: globalVM.isReachable)
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

#Preview {
    ContentView()
        .environmentObject(GlobalVM())
        .environmentObject(ChatVM())
}
