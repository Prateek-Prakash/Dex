//
//  RootView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftData
import SwiftUI

/// The drawer sits underneath; the main screen slides right to reveal it.
/// Opens from the menu button or a swipe from the left edge, and closes with
/// a tap on the uncovered sliver of the main screen or a swipe back left.
struct RootView: View {
    /// Pages the drawer opens on the main screen.
    enum Page: Equatable {
        case chat
        case folders
        /// One folder, by id.
        case folder(UUID)
    }
    
    /// Owned here so the connection survives switching pages; it owns the
    /// server's models.
    @StateObject private var serverVM = ServerVM()
    /// Owned here so the chat survives switching pages.
    @StateObject private var chatVM = ChatVM()
    @Environment(\.modelContext) private var modelContext
    @State var page: Page = .chat
    /// Pages pushed over `page`, reached from another page rather than the
    /// drawer: they have the back button, and the edge swipe is Back. A
    /// drawer pick clears them.
    @State private var routes: [Route] = []
    /// The chat on the chat page when pages were pushed over it, put back
    /// on screen when they're all gone back from (a pushed chat replaced it).
    @State private var chatUnderRoutes: Chat?
    @State private var isHoldingChatUnderRoutes = false
    @State var isDrawerOpen: Bool = false
    @State var showSettingsView: Bool = false
    @Environment(\.displayScale) private var displayScale
    /// Plain state, not `@GestureState`: that snaps back to zero, unanimated,
    /// the moment a finger lifts, so the screen jumped home for a frame
    /// before animating. This settles inside the same animation instead.
    @State private var dragOffset: CGFloat = 0
    /// Whether the current drag moves the drawer: decided on its first move.
    @State private var isDragging: Bool?
    /// True while an edge swipe means Back: on a page with a back button,
    /// the edge swipe goes back and never opens the drawer.
    @State private var isBackSwipe: Bool = false
    /// True while a drag is under way. SwiftUI resets it even when a drag is
    /// cancelled (a call, the app backgrounding), which never calls
    /// `onEnded`; that reset is the cue to settle.
    @GestureState private var isGestureActive: Bool = false

    /// How far a drag must travel, or be flung, to open or close the drawer.
    private let threshold: CGFloat = 0.35
    /// How far a swipe from the left edge can start and still open the drawer.
    private let edgeWidth: CGFloat = 24.0
    /// The open main screen's corners, close to the iPhone display's own.
    private let cornerRadius: CGFloat = 48.0

    var body: some View {
        GeometryReader { proxy in
            let width = drawerWidth(in: proxy.size.width)
            let offset = min(max((isDrawerOpen ? width : 0) + dragOffset, 0), width)
            let progress = width > 0 ? offset / width : 0

            ZStack(alignment: .leading) {
                // Under everything: the drawer is narrower than the screen,
                // and the main screen's rounded corners uncover the rest.
                Color.surfaceDrawer
                    .ignoresSafeArea()
                
                // Full width, so its top bar (glass and line) runs on under
                // the main screen's rounded corner; its content keeps clear
                // of the uncovered sliver.
                DrawerView(
                    sliver: proxy.size.width - width,
                    page: page,
                    currentChatID: chatVM.chat?.id,
                    streamingChatIDs: chatVM.streamingChatIDs,
                    select: { show($0) },
                    openChat: { openChat($0) },
                    renameChat: { chatVM.rename($0, to: $1) },
                    deleteChat: { chatVM.delete($0) },
                    pinChat: { chatVM.togglePin($0) },
                    pinFolder: { chatVM.togglePin($0) },
                    moveChat: { chatVM.move($0, to: $1) },
                    deleteFolder: { deleteFolder($0) },
                    reorderPinned: { chatVM.reorderPinned($0) },
                    openSettings: { showSettingsView = true },
                    newSession: { newSession() }
                )

                // One stack for every page: drawer picks replace its root,
                // everything else pushes onto it.
                NavigationStack(path: $routes) {
                    Group {
                        switch page {
                        case .chat:
                            ContentView(openDrawer: { setDrawer(open: true) }, push: { push($0) })
                        case .folders:
                            FoldersView(openDrawer: { setDrawer(open: true) }, push: { push($0) })
                        case .folder(let id):
                            FolderView(id: id, openDrawer: { setDrawer(open: true) },
                                       push: { push($0) }, leave: { show(.folders) })
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .folder(let id):
                            FolderView(id: id, isPushed: true, push: { push($0) },
                                       leave: { routes.removeAll { $0 == route } })
                        case .chat:
                            PushedChatView(id: route.id, push: { push($0) }, leave: { routes.removeAll { $0 == route } })
                        case .newChat(let folderID):
                            PushedNewChatView(folderID: folderID, push: { push($0) },
                                              leave: { routes.removeAll { $0 == route } })
                        }
                    }
                }
                .tint(Color.ink)
                .onChange(of: routes) { old, new in
                    holdChatUnderRoutes(old: old, new: new)
                }
                    .environmentObject(serverVM)
                    .environmentObject(serverVM.models)
                    .environmentObject(chatVM)
                    .allowsHitTesting(!isDrawerOpen)
                    // Opaque, or the drawer shows through the placeholder.
                    .background(Color.surfaceBase.ignoresSafeArea())
                    // Faded, not dimmed, like Claude: content washes toward
                    // the background while the drawer is open.
                    .overlay {
                        Color.surfaceFade
                            .opacity(0.45 * progress)
                            .ignoresSafeArea()
                            .allowsHitTesting(isDrawerOpen)
                            .onTapGesture { setDrawer(open: false) }
                    }
                    // Rounds the whole screen, safe areas included, as it
                    // slides over; a clip would stop at the safe area.
                    .mask {
                        RoundedRectangle(cornerRadius: cornerRadius * progress, style: .continuous)
                            .ignoresSafeArea()
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius * progress, style: .continuous)
                            .strokeBorder(Color.border.opacity(progress), lineWidth: 1.0 / displayScale)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .shadow(color: Color.shadow.opacity(0.08 * progress), radius: 12.0)
                    .offset(x: offset)
            }
            .simultaneousGesture(drag(width: width))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isDrawerOpen)
        // Before anything can be sent: the chat saves into this store.
        .onAppear { chatVM.context = modelContext }
        // A cancelled drag: `onEnded` never ran, so settle where it was.
        .onChange(of: isGestureActive) {
            if !isGestureActive, isDragging != nil {
                isDragging = nil
                isBackSwipe = false
                setDrawer(open: isDrawerOpen)
            }
        }
        // Here, not on a page, so the drawer's gear opens it from any page.
        .sheet(isPresented: $showSettingsView) {
            SettingsView()
                .environmentObject(serverVM)
                .environmentObject(serverVM.models)
                .presentationBackground(Color.surfaceBase)
        }
    }

    /// Leaves a sliver of the main screen showing, like Claude.
    private func drawerWidth(in total: CGFloat) -> CGFloat {
        max(total - Self.sliver, 0)
    }
    
    static let sliver: CGFloat = 72.0

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12.0)
            .updating($isGestureActive) { _, state, _ in state = true }
            .onChanged { value in
                if isDragging == nil {
                    let fromEdge = isHorizontal(value) && value.startLocation.x <= edgeWidth
                    isBackSwipe = fromEdge && Self.edgeSwipeGoesBack(canGoBack: !routes.isEmpty, isDrawerOpen: isDrawerOpen)
                    isDragging = !isBackSwipe && isHorizontal(value) && (isDrawerOpen || fromEdge)
                }
                guard isDragging == true else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer {
                    isDragging = nil
                    isBackSwipe = false
                }
                // The stack's own swipe handles Back.
                if isBackSwipe { return }
                let travel = value.predictedEndTranslation.width / max(width, 1)
                guard isDragging == true else { return }
                setDrawer(open: Self.settlesOpen(wasOpen: isDrawerOpen, travel: travel, threshold: threshold))
            }
    }
    
    /// Whether a swipe from the left edge is left to the stack's Back rather
    /// than opening the drawer: on any pushed page, while the drawer is closed.
    nonisolated static func edgeSwipeGoesBack(canGoBack: Bool, isDrawerOpen: Bool) -> Bool {
        canGoBack && !isDrawerOpen
    }

    /// Where a released drag settles. `travel` is the predicted end of the
    /// drag (so a quick flick counts) as a share of the drawer's width:
    /// past `threshold` toward the other state switches, anything less
    /// springs back.
    nonisolated static func settlesOpen(wasOpen: Bool, travel: CGFloat, threshold: CGFloat) -> Bool {
        if wasOpen && travel < -threshold { return false }
        if !wasOpen && travel > threshold { return true }
        return wasOpen
    }
    
    /// Vertical drags belong to the lists underneath.
    private func isHorizontal(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height)
    }

    /// Switches the main screen to `page` and closes the drawer onto it.
    private func show(_ page: Page) {
        // A drawer pick starts with nothing pushed, and its chat stays.
        isHoldingChatUnderRoutes = false
        chatUnderRoutes = nil
        routes.removeAll()
        self.page = page
        setDrawer(open: false)
    }

    /// Pushes `route`, or goes back to it if it's already there.
    private func push(_ route: Route) {
        let rootChatID = isHoldingChatUnderRoutes ? chatUnderRoutes?.id : chatVM.chat?.id
        routes = Route.pushing(route, onto: routes, root: page, rootChatID: rootChatID)
    }

    /// Remembers the chat page's chat when pages are first pushed over it,
    /// and puts it back as soon as no pushed chat is left above it: a chat
    /// pushed meanwhile took its place on screen. Pushed chats only sit on
    /// folder pages, so it's back before the chat page shows again, back
    /// animation and edge swipe included.
    private func holdChatUnderRoutes(old: [Route], new: [Route]) {
        guard page == .chat else { return }
        if old.isEmpty, !new.isEmpty {
            chatUnderRoutes = chatVM.chat
            isHoldingChatUnderRoutes = true
        }
        guard isHoldingChatUnderRoutes else { return }
        let hasPushedChat = new.contains(where: \.isChat)
        if !hasPushedChat, chatVM.chat !== chatUnderRoutes {
            if let chat = chatUnderRoutes, !chat.isDeleted, chat.modelContext != nil {
                chatVM.open(chat)
            } else {
                chatVM.reset()
            }
        }
        if new.isEmpty {
            isHoldingChatUnderRoutes = false
            chatUnderRoutes = nil
        }
    }
    
    /// A saved chat on the main screen.
    private func openChat(_ chat: Chat) {
        chatVM.open(chat)
        show(.chat)
    }

    /// Deletes a folder from the drawer. On screen, its page gives way to
    /// Folders, the drawer staying open.
    private func deleteFolder(_ folder: Folder) {
        if page == .folder(folder.id) { page = .folders }
        chatVM.delete(folder)
    }

    /// An empty chat on the main screen, from the drawer. A folder page's
    /// New Session pushes one instead (`Route.newChat`).
    private func newSession() {
        chatVM.reset()
        show(.chat)
    }

    private func setDrawer(open: Bool) {
        if open {
            // The keyboard would otherwise sit over the drawer.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isDrawerOpen = open
            dragOffset = 0
        }
    }
}

#Preview {
    RootView()
        .modelContainer(Storage.inMemory())
}
