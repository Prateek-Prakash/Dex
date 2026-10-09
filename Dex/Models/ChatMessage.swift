//
//  ChatMessage.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// One message in a chat, in memory; `Message` is its stored form.
struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user, assistant, system
    }

    enum Status: String, Sendable {
        case streaming, done, failed, stopped
    }

    var id = Storage.newID()
    var role: Role
    var content: String = ""
    /// The model's reasoning, when it thinks out loud; never sent back.
    var thinking: String?
    /// The web searches and page reads behind a reply, without their text.
    var lookups: [WebLookup]?
    var createdAt = Date()
    /// Order within the chat; breaks ties between equal timestamps.
    var sequence: Int
    /// The model that wrote a reply.
    var model: String?
    var status: Status = .done
    /// Why a reply failed, worded for the transcript.
    var error: String?
    /// The reply's prompt and output sizes, from the stream's final line.
    var promptTokens: Int?
    var outputTokens: Int?
    /// The message this one answers or follows; nil for the first.
    var parentId: String?
    /// Every reply to this message, retried ones included.
    var childrenIds: [String] = []
}
