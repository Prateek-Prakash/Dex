//
//  Storage.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import SwiftData

// Stored in SwiftData on this device only: a cache of what the Open WebUI
// server holds, keyed by the server's ids, so Dex opens fast and reads
// offline.

/// A folder of chats. The server decides what deleting one takes with it;
/// the cache only lets go of its chats.
@Model
final class Folder {
    /// The server's id.
    @Attribute(.unique) var id: String
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Nil when unpinned; also orders the pinned section. Open WebUI has no
    /// pinned folders, so this lives in the folder's `meta` on the server.
    var pinnedAt: Date?
    @Relationship(deleteRule: .nullify, inverse: \Chat.folder)
    var chats: [Chat] = []

    init(id: String = Storage.newID(), name: String) {
        self.id = id
        self.name = name
    }

    /// The Folders page's order: newest first.
    static let newestFirst = [SortDescriptor(\Folder.createdAt, order: .reverse)]

    enum Creation {
        case created(Folder)
        /// Nothing but spaces; nothing saved.
        case blank
        /// Another folder has this name, trimmed, ignoring case; nothing saved.
        case taken(String)
    }

    /// Saves a new folder named `name`, trimmed. Names are unique, ignoring
    /// case.
    static func create(named name: String, in context: ModelContext) -> Creation {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .blank }
        let existing = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        if existing.contains(where: { isSame($0.name, name) }) {
            return .taken(name)
        }
        let folder = Folder(name: name)
        context.insert(folder)
        do {
            try context.save()
        } catch {
            print("Error Saving Folder: \(error.localizedDescription)")
        }
        return .created(folder)
    }

    enum Renaming {
        case renamed
        /// Blank or the same name; nothing changed.
        case unchanged
        /// Another folder has this name; nothing changed.
        case taken(String)
    }

    /// Renames to `name`, trimmed, under the same rule as creating: no other
    /// folder may have it, ignoring case. Changing only the case is fine.
    static func rename(_ folder: Folder, to name: String, in context: ModelContext) -> Renaming {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folder.name else { return .unchanged }
        let others = ((try? context.fetch(FetchDescriptor<Folder>())) ?? []).filter { $0 !== folder }
        if others.contains(where: { isSame($0.name, name) }) {
            return .taken(name)
        }
        folder.name = name
        folder.updatedAt = .now
        do {
            try context.save()
        } catch {
            print("Error Saving Folder: \(error.localizedDescription)")
        }
        return .renamed
    }

    /// The Delete Folder dialog's count line.
    static func chatCount(_ count: Int) -> String {
        switch count {
        case 0: "No Chats"
        case 1: "1 Chat"
        default: "\(count) Chats"
        }
    }

    /// Whether two folder names count as the same: trimmed, ignoring case.
    static func isSame(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

/// A saved chat. Incognito chats never become one.
@Model
final class Chat {
    /// The server's id.
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date = Date()
    /// When a message last arrived, as the server counts it: renames, pins
    /// and moves leave it alone. Sorts Recent.
    var updatedAt: Date = Date()
    /// When the chat was last read; an `updatedAt` after it is unread.
    var lastReadAt: Date?
    /// The server's `updatedAt` when `messages` were last fetched; a newer
    /// one means they are out of date. Nil: never fetched (a title only).
    var messagesSyncedAt: Date?
    /// Nil when unpinned; also orders the pinned section. Whether a chat is
    /// pinned comes from the server; the order is this device's.
    var pinnedAt: Date?
    /// The model of the latest reply.
    var model: String = ""
    /// Nil for a chat on its own.
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message] = []

    init(id: String = Storage.newID(), title: String) {
        self.id = id
        self.title = title
    }

    /// Changed since it was last read.
    var isUnread: Bool {
        updatedAt > (lastReadAt ?? .distantPast)
    }

    /// The chats in the folder with id `folderID`.
    static func inFolder(_ folderID: String) -> Predicate<Chat> {
        #Predicate<Chat> { $0.folder?.id == folderID }
    }

    /// The stored messages in order.
    var sortedMessages: [Message] {
        messages.sorted { $0.sequence < $1.sequence }
    }
}

/// A saved message, one of the branch on show; `ChatMessage` is its
/// in-memory form.
@Model
final class Message {
    /// The server's id.
    @Attribute(.unique) var id: String
    var chat: Chat?
    /// `ChatMessage.Role`'s raw value.
    var role: String = ChatMessage.Role.user.rawValue
    var content: String = ""
    var thinking: String?
    /// `ChatMessage.lookups` as JSON.
    var lookups: String?
    var createdAt: Date = Date()
    var sequence: Int = 0
    var model: String?
    /// `ChatMessage.Status`'s raw value.
    var status: String = ChatMessage.Status.done.rawValue
    var error: String?
    var promptTokens: Int?
    var outputTokens: Int?
    /// The message this one answers or follows; nil for the first.
    var parentId: String?
    /// Every reply to this message, retried ones included: a retry sends
    /// them all, or the server drops the earlier ones.
    var childrenIds: [String] = []

    init(id: String) {
        self.id = id
    }

    /// The messages of the chat with id `chatID`.
    static func inChat(_ chatID: String) -> Predicate<Message> {
        #Predicate<Message> { $0.chat?.id == chatID }
    }

    /// Takes every field but the id and chat from `message`.
    func update(from message: ChatMessage) {
        role = message.role.rawValue
        content = message.content
        thinking = message.thinking
        lookups = message.lookups.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        createdAt = message.createdAt
        sequence = message.sequence
        model = message.model
        status = message.status.rawValue
        error = message.error
        promptTokens = message.promptTokens
        outputTokens = message.outputTokens
        parentId = message.parentId
        childrenIds = message.childrenIds
    }
}

extension ChatMessage {
    /// A stored message, as stored.
    init(_ stored: Message) {
        self.init(
            id: stored.id,
            role: Role(rawValue: stored.role) ?? .user,
            content: stored.content,
            thinking: stored.thinking,
            lookups: stored.lookups.flatMap { try? JSONDecoder().decode([WebLookup].self, from: Data($0.utf8)) },
            createdAt: stored.createdAt,
            sequence: stored.sequence,
            model: stored.model,
            status: Status(rawValue: stored.status) ?? .done,
            error: stored.error,
            promptTokens: stored.promptTokens,
            outputTokens: stored.outputTokens,
            parentId: stored.parentId,
            childrenIds: stored.childrenIds
        )
    }
}

enum Storage {
    static let schema = Schema([Folder.self, Chat.self, Message.self])

    /// A new message, chat or folder id, in the server's form.
    static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Where the cache lives. Named apart from the old iCloud-synced store,
    /// whose files `removeOldStore` deletes.
    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Dex Cache.store")
    }

    /// The app's cache, on this device only.
    static let shared: ModelContainer = {
        removeOldStore()
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // No silent in-memory fallback: chats would vanish on relaunch.
            fatalError("Error Opening Store: \(error.localizedDescription)")
        }
    }()

    /// Deletes the store the iCloud-synced Dex kept, SwiftData's default
    /// file. Its chats were never on the server; the user cleared them.
    static func removeOldStore(in directory: URL = .applicationSupportDirectory) {
        // The store, its journal, and the folders CloudKit mirroring and
        // external storage kept beside it.
        for name in ["default.store", "default.store-shm", "default.store-wal", "default_ckAssets", ".default_SUPPORT"] {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// A throwaway store for tests and previews.
    static func inMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: configuration)
    }
}
