//
//  ContentView.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var globalVM: GlobalVM
    
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    
    
    /// Mock: only changes the button until incognito chats exist.
    @State var isIncognito: Bool = false
    
    @FocusState private var isComposerFocused: Bool
    
    var body: some View {
        NavigationStack {
            // Rechecked each minute, so the greeting turns over on time.
            TimelineView(.everyMinute) { context in
                VStack(spacing: 20.0) {
                    LiveMark(isAlive: globalVM.isReachable)
                    // A quiet caption under the mark, not a second headline.
                    Text(Greeting.text(for: context.date))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .fontDesign(.rounded)
                        .tracking(3.0)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Inside the stack: the stack paints its own system background
            // over anything set behind it.
            .background(Color.appBackground.ignoresSafeArea())
            // Tap anywhere above the message box to put the keyboard away.
            .contentShape(Rectangle())
            .onTapGesture {
                isComposerFocused = false
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        openDrawer()
                    } label: {
                        IconlyIcon(.menu, .action)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isIncognito.toggle()
                        }
                    } label: {
                        // On: inverted icon in a filled circle, like Claude.
                        // The circle is a backdrop, not padding, so the button
                        // stays the menu button's size and its glass stays round.
                        IconlyIcon(.incognito, .action)
                            .foregroundStyle(isIncognito ? Color.appBackground : Color.primary)
                            .background {
                                Circle()
                                    .fill(isIncognito ? Color.primary : Color.clear)
                                    .frame(width: 36.0, height: 36.0)
                            }
                    }
                    .sensoryFeedback(.selection, trigger: isIncognito)
                }
            }
            .navigationTitle(isIncognito ? "Incognito" : "")
            .toolbarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ComposerView(isFocused: $isComposerFocused)
                    .environmentObject(globalVM)
            }
        }
        .tint(Color.primary)
    }
}

#Preview {
    ContentView()
        .environmentObject(GlobalVM())
}
