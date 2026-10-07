//
//  RootView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The drawer sits underneath; the main screen slides right to reveal it.
/// Opens from the menu button or a swipe from the left edge, and closes with
/// a tap on the uncovered sliver of the main screen or a swipe back left.
struct RootView: View {
    /// Pages the drawer opens on the main screen.
    enum Page: Equatable {
        case chat
        case folders
        /// One folder, by name.
        case folder(String)
    }
    
    /// Owned here so the connection survives switching pages.
    @StateObject private var globalVM = GlobalVM()
    @State var page: Page = .chat
    @State var isDrawerOpen: Bool = false
    @State var showSettingsView: Bool = false
    @Environment(\.displayScale) private var displayScale
    /// Plain state, not `@GestureState`: that snaps back to zero, unanimated,
    /// the moment a finger lifts, so the screen jumped home for a frame
    /// before animating. This settles inside the same animation instead.
    @State private var dragOffset: CGFloat = 0
    /// Whether the current drag moves the drawer: decided on its first move.
    @State private var isDragging: Bool?
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
                Color.drawerBackground
                    .ignoresSafeArea()
                
                // Full width, so its top bar (glass and line) runs on under
                // the main screen's rounded corner; its content keeps clear
                // of the uncovered sliver.
                DrawerView(
                    sliver: proxy.size.width - width,
                    page: page,
                    select: { show($0) },
                    openSettings: { showSettingsView = true },
                    newSession: { show(.chat) }
                )

                Group {
                    switch page {
                    case .chat:
                        ContentView(openDrawer: { setDrawer(open: true) })
                    case .folders:
                        FoldersView(openDrawer: { setDrawer(open: true) })
                    case .folder(let name):
                        FolderView(name: name, openDrawer: { setDrawer(open: true) }, newSession: { show(.chat) })
                    }
                }
                    .environmentObject(globalVM)
                    .allowsHitTesting(!isDrawerOpen)
                    // Opaque, or the drawer shows through the placeholder.
                    .background(Color.appBackground.ignoresSafeArea())
                    // Faded, not dimmed, like Claude: content washes toward
                    // the background while the drawer is open.
                    .overlay {
                        Color.drawerFade
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
                            .strokeBorder(Color.drawerBorder.opacity(progress), lineWidth: 1.0 / displayScale)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.08 * progress), radius: 12.0)
                    .offset(x: offset)
            }
            .simultaneousGesture(drag(width: width))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isDrawerOpen)
        // A cancelled drag: `onEnded` never ran, so settle where it was.
        .onChange(of: isGestureActive) {
            if !isGestureActive, isDragging != nil {
                isDragging = nil
                setDrawer(open: isDrawerOpen)
            }
        }
        // Here, not on a page, so the drawer's gear opens it from any page.
        .sheet(isPresented: $showSettingsView) {
            SettingsView()
                .environmentObject(globalVM)
                .presentationBackground(Color.settingsBackground)
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
                    isDragging = isHorizontal(value) && (isDrawerOpen || value.startLocation.x <= edgeWidth)
                }
                guard isDragging == true else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer { isDragging = nil }
                guard isDragging == true else { return }
                let travel = value.predictedEndTranslation.width / max(width, 1)
                setDrawer(open: Self.settlesOpen(wasOpen: isDrawerOpen, travel: travel, threshold: threshold))
            }
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
        self.page = page
        setDrawer(open: false)
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
}
