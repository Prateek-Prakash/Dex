//
//  ChatMessage.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation

/// One message in a chat. Held in memory for now; its fields mirror the
/// stored Message planned for SwiftData, so saving chats is a swap.
struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user, assistant, system
    }

    enum Status: String, Sendable {
        case streaming, done, failed, stopped
    }

    var id = UUID()
    var role: Role
    var content: String = ""
    /// The model's reasoning, when it thinks out loud; never sent back.
    var thinking: String?
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
}
