//
//  CacheSync.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import SwiftData

/// Writes what the server holds into the cache.
enum CacheSync {
    /// The server's title for a chat it hasn't named yet.
    static let unnamedTitle = "New Chat"

    /// A server message as Dex shows it. A reply the server hasn't finished
    /// is still streaming; one it saved with an error failed.
    static func message(_ remote: WebUIMessage, sequence: Int) -> ChatMessage {
        let role = ChatMessage.Role(rawValue: remote.role) ?? .user
        var message = ChatMessage(
            id: remote.id,
            role: role,
            content: remote.content,
            createdAt: remote.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now,
            sequence: sequence,
            model: remote.model,
            promptTokens: remote.usage?.promptTokens,
            outputTokens: remote.usage?.completionTokens,
            parentId: remote.parentId,
            childrenIds: remote.childrenIds
        )
        guard role == .assistant else { return message }
        if let output = remote.output {
            let parts = ReplyParts(output: output, fallback: remote.content)
            message.content = parts.content
            message.thinking = parts.thinking
            message.lookups = parts.lookups.isEmpty ? nil : parts.lookups
        }
        if let error = remote.error {
            message.status = .failed
            message.error = error
        } else if remote.isStopped {
            message.status = .stopped
        } else {
            message.status = remote.done == false ? .streaming : .done
        }
        return message
    }

    /// The branch on show, as Dex shows it.
    static func messages(_ remote: WebUIChat) -> [ChatMessage] {
        remote.chat.history.currentBranch.enumerated().map { message($1, sequence: $0) }
    }

    /// Replaces the cached chat's messages with the server's branch on show,
    /// and takes its title, pin and dates. Messages not on the branch go.
    @MainActor
    static func store(_ remote: WebUIChat, into chat: Chat, context: ModelContext) {
        let messages = messages(remote)
        var records = Dictionary(chat.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(messages.map(\.id))
        for record in chat.messages where !kept.contains(record.id) {
            context.delete(record)
        }
        for message in messages {
            let record = records[message.id] ?? {
                let record = Message(id: message.id)
                context.insert(record)
                record.chat = chat
                records[message.id] = record
                return record
            }()
            record.update(from: message)
        }
        chat.updatedAt = Date(timeIntervalSince1970: TimeInterval(remote.updatedAt))
        chat.messagesSyncedAt = chat.updatedAt
        if let model = messages.last(where: { $0.role == .assistant })?.model { chat.model = model }
        storeDetails(remote, into: chat)
    }

    /// Takes the server's title, pin and creation date: what a rename or
    /// pin in the web UI changes without touching the messages or `updatedAt`.
    @MainActor
    static func storeDetails(_ remote: WebUIChat, into chat: Chat) {
        // The server calls a chat "New Chat" until it names it; Dex's first-line
        // title stands until then.
        if remote.title != CacheSync.unnamedTitle, chat.title != remote.title { chat.title = remote.title }
        chat.createdAt = Date(timeIntervalSince1970: TimeInterval(remote.createdAt))
        if let pinned = remote.pinned, chat.isPinned != pinned { chat.isPinned = pinned }
    }
}

/// Everything the drawer shows, as the server has it.
struct ServerSnapshot: Sendable {
    var chats: [WebUIChatSummary]
    var pinned: Set<String>
    var folders: [WebUIFolder]
    /// Which folder each foldered chat is in.
    var folderOf: [String: String]

    /// The chat list, the pins, the folders, and each folder's chats.
    static func fetch(_ client: WebUIClient) async throws -> ServerSnapshot {
        async let chats = client.chats()
        async let pinned = client.pinnedChats()
        async let folders = client.folders()
        let list = try await folders
        let folderOf = try await withThrowingTaskGroup(of: (String, [WebUIChatSummary]).self) { group in
            for folder in list {
                group.addTask { (folder.id, try await client.chats(inFolder: folder.id)) }
            }
            var folderOf: [String: String] = [:]
            for try await (folderID, chats) in group {
                for chat in chats { folderOf[chat.id] = folderID }
            }
            return folderOf
        }
        return ServerSnapshot(chats: try await chats, pinned: Set(try await pinned.map(\.id)), folders: list, folderOf: folderOf)
    }
}

extension CacheSync {
    /// Makes the cache's folders and chats match `snapshot`: new ones added,
    /// changed ones updated, ones gone from the server removed. Left alone:
    /// chats in `keep`, open or replying here (a new one may not be listed
    /// yet).
    @MainActor
    static func apply(_ snapshot: ServerSnapshot, to context: ModelContext, keep: Set<String>) {
        let localFolders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        var folders = Dictionary(localFolders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteFolderIDs = Set(snapshot.folders.map(\.id))
        for remote in snapshot.folders {
            let folder = folders[remote.id] ?? {
                let folder = Folder(id: remote.id, name: remote.name)
                context.insert(folder)
                folders[remote.id] = folder
                return folder
            }()
            if folder.name != remote.name { folder.name = remote.name }
            folder.createdAt = Date(timeIntervalSince1970: TimeInterval(remote.createdAt))
            folder.updatedAt = Date(timeIntervalSince1970: TimeInterval(remote.updatedAt))
        }
        for folder in localFolders where !remoteFolderIDs.contains(folder.id) {
            context.delete(folder)
            folders[folder.id] = nil
        }

        let localChats = (try? context.fetch(FetchDescriptor<Chat>())) ?? []
        var chats = Dictionary(localChats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteChats = snapshot.chats.filter { $0.archived != true }
        let remoteChatIDs = Set(remoteChats.map(\.id))
        for remote in remoteChats {
            let chat = chats[remote.id] ?? {
                let chat = Chat(id: remote.id, title: remote.title)
                context.insert(chat)
                chats[remote.id] = chat
                return chat
            }()
            if remote.title != unnamedTitle, chat.title != remote.title { chat.title = remote.title }
            chat.createdAt = Date(timeIntervalSince1970: TimeInterval(remote.createdAt))
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(remote.updatedAt))
            // A reply finishing here may have saved a newer time than the list's.
            if updatedAt > chat.updatedAt { chat.updatedAt = updatedAt }
            if let lastReadAt = remote.lastReadAt.map({ Date(timeIntervalSince1970: TimeInterval($0)) }),
               lastReadAt > (chat.lastReadAt ?? .distantPast) {
                chat.lastReadAt = lastReadAt
            }
            if chat.isActive != (remote.active == true) { chat.isActive = remote.active == true }
            let isPinned = snapshot.pinned.contains(remote.id)
            if chat.isPinned != isPinned { chat.isPinned = isPinned }
            let folder = snapshot.folderOf[remote.id].flatMap { folders[$0] }
            if chat.folder !== folder { chat.folder = folder }
        }
        for chat in localChats where !remoteChatIDs.contains(chat.id) && !keep.contains(chat.id) {
            context.delete(chat)
        }
    }
}
