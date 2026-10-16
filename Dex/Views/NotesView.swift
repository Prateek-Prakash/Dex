//
//  NotesView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/14/26.
//

import SwiftData
import SwiftUI

/// Notes, opened from the drawer: pinned ones first, then the rest, each
/// newest change first, with the note's first line under its title. New Note
/// makes one and opens it; a long press pins, renames or deletes one. A note
/// opens pushed, with the back button and swipe.
struct NotesView: View {
    /// Opens the drawer behind this screen.
    var openDrawer: () -> Void = {}
    /// Pushes a page over this one.
    var push: (Route) -> Void = { _ in }

    @EnvironmentObject private var chatVM: ChatVM
    @Query(sort: Note.newestFirst) private var notes: [Note]
    /// The note whose Rename or Delete dialog is up.
    @State private var noteToRename: Note?
    @State private var noteToDelete: Note?
    /// Set while New Note waits on the server.
    @State private var isCreating = false

    /// Section headers, a step above body, like the drawer's; follow Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var headerTextSize: CGFloat = 17.0

    var body: some View {
        PageScaffold(title: "Notes", pillTitle: "New Note", openDrawer: openDrawer, pillAction: newNote) {
            List {
                let pinned = notes.filter(\.isPinned)
                if !pinned.isEmpty {
                    section("Pinned", pinned)
                    section("Notes", notes.filter { !$0.isPinned })
                } else {
                    // Only notes: no header.
                    ForEach(notes) { row($0) }
                }
            }
            .tileList()
            .scrollContentBackground(.hidden)
            .refreshable { await chatVM.refreshList() }
            .emptyList(notes.isEmpty, icon: .note, title: "No Notes Yet")
        }
        .noteActionAlerts(renaming: $noteToRename, deleting: $noteToDelete,
                          rename: { chatVM.rename($0, to: $1) }, delete: { chatVM.delete($0) })
    }

    @ViewBuilder
    private func section(_ title: String, _ notes: [Note]) -> some View {
        if !notes.isEmpty {
            Section {
                ForEach(notes) { row($0) }
            } header: {
                Text(title)
                    .font(.system(size: headerTextSize, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        Button {
            push(.note(note.id))
        } label: {
            TileRow(icon: .note, title: note.displayTitle, subtitle: note.preview.isEmpty ? "Empty" : note.preview)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ItemActions(isPinned: note.isPinned, pin: { chatVM.togglePin(note) },
                        rename: { noteToRename = note }, delete: { noteToDelete = note })
        }
        .tileRowInList()
    }

    /// Makes a note on the server and opens it.
    private func newNote() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            if let note = await chatVM.createNote() { push(.note(note.id)) }
            isCreating = false
        }
    }
}

/// One note, found by id so a rename or refresh shows at once: formatted
/// like a reply, under its title, with ⋯ for Pin, Rename and Delete. Edit
/// switches to its Markdown as plain text, saved a second after typing
/// stops, and on Done or leaving; until it's renamed, its first line is its
/// title. A new note opens in Edit. Read again from the server on opening.
/// Deleted anywhere, it leaves; made here and left empty and untitled, it's
/// deleted.
struct NoteView: View {
    /// Goes back from it once it's gone.
    var leave: () -> Void = {}

    @EnvironmentObject private var chatVM: ChatVM
    @Query private var notes: [Note]
    @State private var noteToRename: Note?
    @State private var noteToDelete: Note?
    @State private var isEditing = false
    /// The text being edited; written into the note as it changes.
    @State private var text = ""
    @FocusState private var isFocused: Bool
    private let id: String

    init(id: String, leave: @escaping () -> Void = {}) {
        self.id = id
        self.leave = leave
        _notes = Query(filter: #Predicate<Note> { $0.id == id })
    }

    private var note: Note? { notes.first }

    var body: some View {
        PageScaffold(title: note?.displayTitle ?? "", pillTitle: "", showsDrawerButton: false) {
            if isEditing {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    // The editor insets its text a few points itself: this
                    // lines it up with the chat's text column.
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.m)
                    .toolbarGlassEdge()
                    .onChange(of: text) {
                        if let note { chatVM.edit(note, markdown: text) }
                    }
                    // A newer copy (read on opening, a refresh) before anything is
                    // typed: the editor takes it, so typing doesn't save over it.
                    .onChange(of: note?.markdown) {
                        guard let markdown = note?.markdown, markdown != text,
                              !chatVM.editingNoteIDs.contains(id) else { return }
                        text = markdown
                    }
            } else {
                reading
            }
        } actions: {
            if let note {
                ItemActions(isPinned: note.isPinned, pin: { chatVM.togglePin(note) },
                            rename: { noteToRename = note }, delete: { noteToDelete = note })
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditing ? done() : startEditing()
                } label: {
                    IconlyIcon(isEditing ? .check : .edit, .action)
                }
                .accessibilityLabel(isEditing ? "Done" : "Edit")
            }
        }
        .noteActionAlerts(renaming: $noteToRename, deleting: $noteToDelete,
                          rename: { chatVM.rename($0, to: $1) }, delete: { chatVM.delete($0) })
        // Deleted here or on the server: nothing left to show.
        .onChange(of: note == nil) {
            if note == nil { leave() }
        }
        .onAppear {
            // A new note: straight to typing.
            if let note, note.title.isEmpty, note.markdown.isEmpty { startEditing() }
        }
        .task { await chatVM.reload(note: id) }
        .onDisappear {
            let isNew = chatVM.newNoteIDs.remove(id) != nil
            guard let note, !note.isDeleted else { return }
            // A note made here and left as it came (no title, no text) isn't
            // kept; a blank one from the web page is.
            if isNew, note.title.isEmpty, note.markdown.isEmpty {
                chatVM.delete(note)
            } else {
                chatVM.flush(note)
            }
        }
    }

    private var reading: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let note, !note.markdown.isEmpty {
                    ChatMarkdownView(text: note.markdown)
                        .equatable()
                        .textSelection(.enabled)
                } else {
                    // An empty note: tap to start writing.
                    Button(action: startEditing) {
                        Text("Empty")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            // The chat's text column; below the bar, every screen's gap.
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbarGlassEdge()
    }

    private func startEditing() {
        text = note?.markdown ?? ""
        isEditing = true
        // Once the editor is there to take it.
        DispatchQueue.main.async { isFocused = true }
    }

    /// Back to the formatted note; what was typed is saved now.
    private func done() {
        isFocused = false
        isEditing = false
        if let note { chatVM.flush(note) }
    }
}

extension Note {
    /// Its name as shown: an untitled note is "New Note".
    var displayTitle: String { title.isEmpty ? "New Note" : title }
}

extension View {
    /// The Rename and Delete dialogs for whichever note is set in
    /// `renaming` or `deleting`; each clears it when it closes.
    func noteActionAlerts(renaming: Binding<Note?>, deleting: Binding<Note?>,
                          rename: @escaping (Note, String) -> Void, delete: @escaping (Note) -> Void) -> some View {
        modifier(NoteActionAlerts(renaming: renaming, deleting: deleting, rename: rename, delete: delete))
    }
}

private struct NoteActionAlerts: ViewModifier {
    @Binding var renaming: Note?
    @Binding var deleting: Note?
    let rename: (Note, String) -> Void
    let delete: (Note) -> Void

    @State private var newTitle = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename Note", isPresented: present($renaming), presenting: renaming) { note in
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename(note, newTitle) }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Starts from the current title, so a small fix is a small edit.
            .onChange(of: renaming) {
                if let note = renaming { newTitle = note.title }
            }
            .alert("Delete Note", isPresented: present($deleting), presenting: deleting) { note in
                Button("Delete", role: .destructive) { delete(note) }
                Button("Cancel", role: .cancel) {}
            } message: { note in
                Text(note.displayTitle)
            }
    }

    private func present(_ note: Binding<Note?>) -> Binding<Bool> {
        Binding(get: { note.wrappedValue != nil }, set: { if !$0 { note.wrappedValue = nil } })
    }
}

#Preview {
    NotesView()
        .modelContainer(Storage.inMemory())
        .environmentObject(ChatVM())
}
