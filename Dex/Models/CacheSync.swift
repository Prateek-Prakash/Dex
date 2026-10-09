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
        if remote.pinned == true, chat.pinnedAt == nil { chat.pinnedAt = .now }
        if remote.pinned == false, chat.pinnedAt != nil { chat.pinnedAt = nil }
    }
}
