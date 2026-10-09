//
//  WebUIModels.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation

/// A chat as `/api/v1/chats/list` and friends list it: no messages.
struct WebUIChatSummary: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let updatedAt: Int
    let createdAt: Int
    let lastReadAt: Int?
    /// A reply is running on the server.
    var active: Bool?
    var archived: Bool?

    /// Changed since it was last read, and no reply still running: the
    /// server's own unread rule.
    var isUnread: Bool { updatedAt > (lastReadAt ?? 0) && active != true }

    enum CodingKeys: String, CodingKey {
        case id, title, active, archived
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case lastReadAt = "last_read_at"
    }
}

/// A folder. Open WebUI nests them; Dex shows every folder at one level.
struct WebUIFolder: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let parentId: String?
    let createdAt: Int
    let updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A saved chat with its whole message tree, from `/api/v1/chats/{id}`.
struct WebUIChat: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let pinned: Bool?
    let folderId: String?
    let updatedAt: Int
    let createdAt: Int
    let chat: Body

    struct Body: Decodable, Sendable {
        let history: WebUIHistory
        let tags: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case id, title, pinned, chat
        case folderId = "folder_id"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

/// Every message of a chat, as a tree: a retried reply is a sibling of the
/// first, and `currentId` is the end of the branch on show.
struct WebUIHistory: Decodable, Sendable {
    let currentId: String?
    let messages: [String: WebUIMessage]

    /// The branch on show, oldest first: `currentId` back up to the root.
    var currentBranch: [WebUIMessage] {
        var branch: [WebUIMessage] = []
        var seen = Set<String>()
        var id = currentId
        // `seen` stops a malformed tree that loops.
        while let next = id, let message = messages[next], seen.insert(next).inserted {
            branch.append(message)
            id = message.parentId
        }
        return branch.reversed()
    }
}

struct WebUIMessage: Decodable, Sendable, Identifiable {
    let id: String
    let parentId: String?
    let childrenIds: [String]
    let role: String
    let content: String
    /// Assistant replies only; false while running, and after a stop.
    let done: Bool?
    let model: String?
    let timestamp: Int?
    let usage: WebUIUsage?
    /// What the reply did, in order: thinking, lookups, their results, text.
    let output: [WebUIOutputItem]?
    /// Why a reply failed, as the server worded it.
    let error: String?
    /// Stopped in Dex, which saved what showed of it.
    let isStopped: Bool

    /// Dex's mark on a reply it stopped.
    static let stoppedKey = "dex_stopped"

    enum CodingKeys: String, CodingKey {
        case id, parentId, childrenIds, role, content, done, model, timestamp, usage, output, error
        case isStopped = "dex_stopped"
    }

    /// `error` is `{"content": "…"}`, or a bare string.
    private struct ErrorBody: Decodable { let content: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        childrenIds = try container.decodeIfPresent([String].self, forKey: .childrenIds) ?? []
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        done = try container.decodeIfPresent(Bool.self, forKey: .done)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        timestamp = try container.decodeIfPresent(Int.self, forKey: .timestamp)
        usage = try container.decodeIfPresent(WebUIUsage.self, forKey: .usage)
        output = try container.decodeIfPresent([WebUIOutputItem].self, forKey: .output)
        isStopped = (try? container.decodeIfPresent(Bool.self, forKey: .isStopped)) ?? false
        if let body = try? container.decodeIfPresent(ErrorBody.self, forKey: .error) {
            error = body.content ?? "The reply failed"
        } else {
            error = try? container.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

/// A reply's token counts.
struct WebUIUsage: Decodable, Sendable, Equatable {
    let promptTokens: Int?
    let completionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

/// One step of a reply, in the OpenAI Responses shape Open WebUI stores.
enum WebUIOutputItem: Decodable, Sendable, Equatable {
    case reasoning(id: String, text: String, duration: Int?)
    /// `arguments` is the raw JSON the model wrote, e.g. `{"query": "…"}`.
    case functionCall(id: String, callID: String, name: String, arguments: String)
    case functionCallOutput(callID: String, text: String)
    case message(id: String, text: String)
    /// A kind Dex doesn't show.
    case other(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, id, content, duration, name, arguments, output
        case callID = "call_id"
    }

    /// `content` and `output` are lists of text parts.
    private struct Part: Decodable { let text: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        func text(_ key: CodingKeys) -> String {
            ((try? container.decodeIfPresent([Part].self, forKey: key)) ?? nil)?
                .compactMap(\.text).joined() ?? ""
        }
        switch type {
        case "reasoning":
            self = .reasoning(id: try container.decode(String.self, forKey: .id), text: text(.content),
                              duration: try? container.decodeIfPresent(Int.self, forKey: .duration))
        case "function_call":
            self = .functionCall(id: try container.decode(String.self, forKey: .id),
                                 callID: try container.decode(String.self, forKey: .callID),
                                 name: try container.decode(String.self, forKey: .name),
                                 arguments: try container.decodeIfPresent(String.self, forKey: .arguments) ?? "")
        case "function_call_output":
            self = .functionCallOutput(callID: try container.decode(String.self, forKey: .callID), text: text(.output))
        case "message":
            self = .message(id: try container.decode(String.self, forKey: .id), text: text(.content))
        default:
            self = .other(type: type)
        }
    }
}

/// A model from `/api/models`, as Dex lists and describes it.
struct WebUIModel: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Hidden in Open WebUI's model settings.
    let isHidden: Bool
    /// Open WebUI's arena pseudo-model.
    let isArena: Bool
    /// In memory on the server now.
    let isLoaded: Bool
    /// Bytes on disk; nil for a model Ollama doesn't serve.
    let size: Int?
    let digest: String?
    /// When it was last pulled or changed.
    let modifiedAt: Date?
    let details: Details?
    /// What it can do, as Ollama names it: "completion", "tools",
    /// "thinking", "vision", "audio", "embedding".
    let capabilities: [String]

    struct Details: Decodable, Sendable, Hashable {
        let format: String?
        let family: String?
        let parameterSize: String?
        let quantizationLevel: String?
        /// The most context the model takes, in tokens.
        let contextLength: Int?

        enum CodingKeys: String, CodingKey {
            case format, family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
            case contextLength = "context_length"
        }
    }

    /// Shown in Dex's model list.
    var isListed: Bool { !isHidden && !isArena }

    /// "gemma4:12b" -> "gemma4"; "library/model" names keep their namespace.
    var baseName: String { String(id.split(separator: ":", maxSplits: 1).first ?? Substring(id)) }

    /// "gemma4:12b" -> "12b"; a name without a tag is "latest".
    var tag: String {
        let parts = id.split(separator: ":", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : "latest"
    }

    /// The hash as Ollama shows it: its first 12 characters.
    var shortDigest: String { String((digest ?? "").prefix(12)) }

    private enum CodingKeys: String, CodingKey { case id, name, info, arena, ollama, loaded }
    private struct Info: Decodable { let meta: Meta? }
    private struct Meta: Decodable { let hidden: Bool? }
    private struct Ollama: Decodable {
        let size: Int?
        let digest: String?
        let modifiedAt: String?
        let details: Details?
        let capabilities: [String]?
        enum CodingKeys: String, CodingKey {
            case size, digest, details, capabilities
            case modifiedAt = "modified_at"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        let info = try? container.decodeIfPresent(Info.self, forKey: .info)
        isHidden = info?.meta?.hidden ?? false
        isArena = (try? container.decodeIfPresent(Bool.self, forKey: .arena)) ?? false
        isLoaded = (try? container.decodeIfPresent(Bool.self, forKey: .loaded)) ?? false
        let ollama = try? container.decodeIfPresent(Ollama.self, forKey: .ollama)
        size = ollama?.size
        digest = ollama?.digest
        modifiedAt = ollama?.modifiedAt.flatMap(Self.date)
        details = ollama?.details
        capabilities = ollama?.capabilities ?? []
    }

    /// Ollama's times carry up to nine fractional digits and an offset
    /// ("2026-10-07T19:39:04.6354653-04:00"); the fraction is dropped.
    static func date(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

/// More about a model, from Ollama's `show` through the server's proxy:
/// what it was built from, by whom, and under which license.
struct WebUIModelInfo: Decodable, Sendable, Equatable {
    let baseModel: String?
    let maker: String?
    let license: String?

    private enum CodingKeys: String, CodingKey { case modelInfo = "model_info" }

    init(baseModel: String?, maker: String?, license: String?) {
        self.baseModel = baseModel
        self.maker = maker
        self.license = license
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let info = (try? container.decodeIfPresent([String: JSONValue].self, forKey: .modelInfo)) ?? [:]
        baseModel = info["general.base_model.0.name"]?.string ?? info["general.basename"]?.string
        maker = info["general.base_model.0.organization"]?.string ?? info["general.organization"]?.string
        license = info["general.license"]?.string
    }
}

/// `POST /api/chat/completions` as a background job: the server saves the
/// reply into the chat and streams it over the socket.
struct WebUIReplyRequest: Encodable, Sendable {
    struct UserMessage: Encodable, Sendable, Equatable {
        let id: String
        let parentId: String?
        /// Every reply to this message, the new one last: a retry lists the
        /// earlier replies too, or the server drops them from the tree.
        let childrenIds: [String]
        var role = "user"
        let content: String
        let timestamp: Int
        let models: [String]

        enum CodingKeys: String, CodingKey { case id, parentId, childrenIds, role, content, timestamp, models }

        /// `parentId` is sent even when null, as the web UI sends it.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(parentId, forKey: .parentId)
            try container.encode(childrenIds, forKey: .childrenIds)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(models, forKey: .models)
        }
    }

    struct Features: Encodable, Sendable {
        var webSearch = true
        enum CodingKeys: String, CodingKey { case webSearch = "web_search" }
    }

    struct BackgroundTasks: Encodable, Sendable {
        var titleGeneration = true
        var tagsGeneration = true
        enum CodingKeys: String, CodingKey {
            case titleGeneration = "title_generation"
            case tagsGeneration = "tags_generation"
        }
    }

    let model: String
    var stream = true
    /// The socket's id: where the server sends the live reply. Without it
    /// the server runs no tools and saves nothing.
    let sessionID: String
    /// The new reply's id, chosen here.
    let id: String
    /// Nil starts a new chat.
    let chatID: String?
    /// Nil in a new chat; the previous reply in a follow-up; the question
    /// itself in a retry.
    let parentID: String?
    let userMessage: UserMessage
    /// Only a new chat sends its question here; the server rebuilds the
    /// history of a saved chat itself.
    var messages: [[String: String]]?
    var features = Features()
    var backgroundTasks: BackgroundTasks?
    /// The model's settings for this reply: the context window, the same
    /// every time, since a different one makes Ollama reload the model.
    var params = ["num_ctx": WebUIReplyRequest.contextLength]

    /// The context window every reply asks for, in tokens.
    static let contextLength = 65_536

    enum CodingKeys: String, CodingKey {
        case model, stream, id, messages, features, params
        case sessionID = "session_id"
        case chatID = "chat_id"
        case parentID = "parent_id"
        case userMessage = "user_message"
        case backgroundTasks = "background_tasks"
    }

    /// `parent_id` is always sent: null is how the server knows a chat is new.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(stream, forKey: .stream)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(chatID, forKey: .chatID)
        try container.encode(parentID, forKey: .parentID)
        try container.encode(userMessage, forKey: .userMessage)
        try container.encodeIfPresent(messages, forKey: .messages)
        try container.encode(features, forKey: .features)
        try container.encodeIfPresent(backgroundTasks, forKey: .backgroundTasks)
        try container.encode(params, forKey: .params)
    }

    /// Temporary chats live only in the socket stream and are never saved.
    static func temporaryChatID(sessionID: String) -> String { "local:" + sessionID }
}
