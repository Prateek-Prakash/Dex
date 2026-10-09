//
//  Storage.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import SwiftData
import UIKit

// Stored in SwiftData and synced through the iCloud private database.
// CloudKit's rules shape every model here: no unique attributes, every
// property optional or defaulted, every relationship optional with an inverse.

/// A folder of chats. Deleting it deletes its chats.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Nil when unpinned; also orders the pinned section.
    var pinnedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \Chat.folder)
    var chats: [Chat]? = []

    init(name: String) {
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
    /// case. CloudKit can't enforce that, so two devices creating one name
    /// at the same moment can still both keep theirs.
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
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// When a message last arrived; sorts Recent.
    var lastMessageAt: Date = Date()
    /// Nil when unpinned; also orders the pinned section.
    var pinnedAt: Date?
    /// The model of the latest reply.
    var model: String = ""
    var contextLength: Int = OllamaChatRequest.contextLength
    /// Nil for a chat on its own.
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]? = []

    init(title: String) {
        self.title = title
    }

    /// The chats in the folder with id `folderID`.
    static func inFolder(_ folderID: UUID) -> Predicate<Chat> {
        #Predicate<Chat> { $0.folder?.id == folderID }
    }

    /// The stored messages in order.
    var sortedMessages: [Message] {
        (messages ?? []).sorted { $0.sequence < $1.sequence }
    }
}

/// A saved message; `ChatMessage` is its in-memory form.
@Model
final class Message {
    var id: UUID = UUID()
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
    /// While a reply streams: when it last got a checkpoint, and the device
    /// streaming it (`thisDevice`). Nil for anything else.
    var checkpointAt: Date?
    var replyDevice: String?

    init(id: UUID) {
        self.id = id
    }

    /// How often a reply streaming here is saved, tokens or not, so other
    /// devices see it come in and know it's alive.
    static let checkpointInterval: TimeInterval = 5
    /// How long a reply stored streaming counts as still coming without a
    /// new checkpoint: well past the interval, since sync can lag.
    static let liveWindow: TimeInterval = 90
    /// This device, as `replyDevice` names it.
    static let thisDevice = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

    /// Whether a reply stored streaming is still coming on another device:
    /// checkpointed lately, and not by this one (a reply streaming here is
    /// shown from memory; one stored from here but not running was cut off).
    func isLiveElsewhere(now: Date = .now) -> Bool {
        guard status == ChatMessage.Status.streaming.rawValue, let checkpointAt,
              replyDevice != Self.thisDevice else { return false }
        return now.timeIntervalSince(checkpointAt) < Self.liveWindow
    }

    /// Replies stored streaming, live or cut off.
    static let streaming = #Predicate<Message> { $0.status == "streaming" }

    /// The messages of the chat with id `chatID`.
    static func inChat(_ chatID: UUID) -> Predicate<Message> {
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
    }
}

extension ChatMessage {
    /// A stored message. A reply stored streaming is still coming only while
    /// another device keeps checkpointing it; otherwise it was cut off by a
    /// quit and can't pick up again.
    init(_ stored: Message, now: Date = .now) {
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
            outputTokens: stored.outputTokens
        )
        if status == .streaming, !stored.isLiveElsewhere(now: now) {
            status = .stopped
        }
    }
}

enum Storage {
    static let cloudKitContainer = "iCloud.Teekzilla.Dex"
    static let schema = Schema([Folder.self, Chat.self, Message.self])

    /// The app's store, synced through iCloud.
    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainer))
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // No silent in-memory fallback: chats would vanish on relaunch.
            fatalError("Error Opening Store: \(error.localizedDescription)")
        }
    }()

    /// A throwaway store for tests and previews; never synced.
    static func inMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: configuration)
    }
}
