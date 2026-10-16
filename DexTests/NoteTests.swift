//
//  NoteTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/14/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

/// Notes as the server sends them, and kept in the cache.
@MainActor
struct NoteTests {
    static func note(_ id: String, _ title: String, md: String = "Text", pinned: Bool = false,
                     updated: Int = 1_792_029_439_764_560_369) -> WebUINote {
        let content = String(decoding: try! JSONEncoder().encode(md), as: UTF8.self)
        let json = #"{"id":"\#(id)","title":"\#(title)","data":{"content":{"md":\#(content),"html":null,"json":null}},"is_pinned":\#(pinned),"created_at":1792029000000000000,"updated_at":\#(updated)}"#
        return try! JSONDecoder().decode(WebUINote.self, from: Data(json.utf8))
    }

    @Test func notesDecodeWithNanosecondTimes() throws {
        let note = Self.note("n1", "Server Setup", md: "# Server Setup\n\nOllama", pinned: true)
        #expect(note.markdown == "# Server Setup\n\nOllama")
        #expect(note.isPinned)
        #expect(abs(note.updatedAt.timeIntervalSince1970 - 1_792_029_439.76) < 0.01)
        // A list item has no created time and maybe no content.
        let bare = try JSONDecoder().decode(WebUINote.self, from: Data(#"{"id":"n2","title":"T","data":null,"updated_at":1792029439}"#.utf8))
        #expect(bare.markdown == "")
        #expect(!bare.isPinned)
        #expect(bare.createdAt == nil)
        #expect(bare.updatedAt.timeIntervalSince1970 == 1_792_029_439)
        #expect(WebUINote.date(1_792_029_439_123).timeIntervalSince1970 == 1_792_029_439.123)
    }

    @Test func previewSkipsTheTitleAndMarks() {
        #expect(Note.preview("# Trip\n\n- **16 GB** minimum", title: "Trip") == "16 GB minimum")
        #expect(Note.preview("```swift\nlet x = 1\n```", title: "Code") == "let x = 1")
        #expect(Note.preview("*   First item\n    \n", title: "List") == "First item")
        #expect(Note.preview("1. Step one", title: "Steps") == "Step one")
        #expect(Note.preview("", title: "Empty") == "")
    }

    @Test func theFirstLineIsTheTitleUntilRenamed() {
        #expect(Note.autoTitle("## Weekend Plans\nHike") == "Weekend Plans")
        #expect(Note.autoTitle("\n\n- **Milk** and eggs") == "Milk and eggs")
        #expect(Note.autoTitle("") == "")
        let note = Note(id: "n", title: "")
        #expect(note.hasAutoTitle)
        note.markdown = "Plans for the weekend"
        note.title = "Plans for the weekend"
        #expect(note.hasAutoTitle)
        // Its preview doesn't repeat the title.
        #expect(note.preview == "")
        note.title = "Renamed"
        #expect(!note.hasAutoTitle)
        #expect(note.preview == "Plans for the weekend")
    }

    private func notes(_ context: ModelContext) -> [Note] {
        (try? context.fetch(FetchDescriptor<Note>())) ?? []
    }

    @Test func cacheFollowsTheServersNotes() throws {
        let context = ModelContext(Storage.inMemory())
        CacheSync.apply([Self.note("n1", "One", md: "A"), Self.note("n2", "Two")], to: context, keep: [])
        #expect(Set(notes(context).map(\.id)) == ["n1", "n2"])
        CacheSync.apply([Self.note("n1", "One Renamed", md: "B", pinned: true)], to: context, keep: [])
        let one = try #require(notes(context).first)
        #expect(notes(context).count == 1)
        #expect(one.title == "One Renamed")
        #expect(one.markdown == "B")
        #expect(one.isPinned)
    }

    @Test func notesBeingEditedHereStay() throws {
        let context = ModelContext(Storage.inMemory())
        let editing = Note(id: "n1", title: "Draft")
        editing.markdown = "Typed here"
        context.insert(editing)
        let fresh = Note(id: "n3", title: "Brand New")
        context.insert(fresh)
        CacheSync.apply([Self.note("n1", "Old", md: "Old text")], to: context, keep: ["n1", "n3"])
        #expect(editing.markdown == "Typed here")
        #expect(Set(notes(context).map(\.id)) == ["n1", "n3"])
    }

    @Test func unreadableNotesLeaveTheCacheAlone() throws {
        let context = ModelContext(Storage.inMemory())
        context.insert(Note(id: "n1", title: "Kept"))
        CacheSync.apply(ServerSnapshot(chats: [], pinned: [], folders: [], folderOf: [:], notes: nil), to: context, keep: [])
        #expect(notes(context).map(\.id) == ["n1"])
        CacheSync.apply(ServerSnapshot(chats: [], pinned: [], folders: [], folderOf: [:], notes: []), to: context, keep: [])
        #expect(notes(context).isEmpty)
    }
}
