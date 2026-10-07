//
//  ChatVM.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import Foundation
import SwiftData

/// The open chat. `messages` is its working copy; unless incognito, each
/// message is saved when it is sent and when its reply finishes, never per
/// streamed token.
@MainActor
final class ChatVM: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    /// Incognito chats are never saved.
    @Published var isIncognito: Bool = false
    /// The saved chat on screen; nil until a saved chat's first message.
    @Published private(set) var chat: Chat?
    /// Where chats are saved; nil keeps everything in memory (previews).
    var context: ModelContext?

    private var streamTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    /// The saved chat's stored messages, by id.
    private var records: [UUID: Message] = [:]

    var isStreaming: Bool {
        messages.last?.status == .streaming
    }

    /// Tokens the chat fills, against `OllamaChatRequest.contextLength`.
    var contextUsed: Int? {
        Self.contextUsed(messages)
    }

    /// The last finished reply's prompt plus output. A prompt carries the
    /// whole chat, so it can't be smaller than the reply before it; when
    /// Ollama reports less (it may count only what it didn't have cached),
    /// the running total stands in, so the ring never shrinks as a chat grows.
    nonisolated static func contextUsed(_ messages: [ChatMessage]) -> Int? {
        var total: Int?
        for message in messages.sorted(by: { $0.sequence < $1.sequence })
        where message.role == .assistant && message.promptTokens != nil {
            let prompt = max(message.promptTokens ?? 0, total ?? 0)
            total = prompt + (message.outputTokens ?? 0)
        }
        return total
    }

    /// After every message here and every stored one: another device may
    /// have added to the chat since it opened, and a repeated number would
    /// mix the two orders on the next open.
    private var nextSequence: Int {
        let stored = chat?.messages?.map(\.sequence) ?? []
        return ((messages.map(\.sequence) + stored).max() ?? -1) + 1
    }

    /// Whether the last reply can be asked for again.
    var canRetry: Bool {
        guard let last = messages.last else { return false }
        return last.role == .assistant && (last.status == .failed || last.status == .stopped)
    }

    func send(_ text: String, client: OllamaClient?, model: OllamaModel?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        messages.append(ChatMessage(role: .user, content: text, sequence: nextSequence))
        save(messages[messages.count - 1])
        reply(client: client, model: model)
    }

    /// Replaces the last failed or stopped reply with a new one.
    func retry(client: OllamaClient?, model: OllamaModel?) {
        guard canRetry else { return }
        forget(messages.removeLast().id)
        reply(client: client, model: model)
    }

    /// Ends the reply where it is; what streamed so far stays.
    func stop() {
        streamTask?.cancel()
    }

    /// A new, empty chat.
    func reset() {
        leave()
        isIncognito = false
    }

    /// Puts a saved chat on screen.
    func open(_ chat: Chat) {
        guard chat !== self.chat else { return }
        leave()
        isIncognito = false
        self.chat = chat
        let stored = chat.sortedMessages
        records = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        messages = stored.map(ChatMessage.init)
    }

    /// Renames a saved chat. A blank name changes nothing; a rename made
    /// while the chat is being named wins over the generated name.
    func rename(_ chat: Chat, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != chat.title else { return }
        chat.title = title
        chat.updatedAt = .now
        commit()
    }

    /// Deletes a saved chat, and its messages; an empty chat replaces it on screen.
    func delete(_ chat: Chat) {
        if chat === self.chat { reset() }
        context?.delete(chat)
        commit()
    }

    /// Deletes a folder and every chat in it; if one of them is on screen,
    /// an empty chat replaces it.
    func delete(_ folder: Folder) {
        if let chat, chat.folder === folder { reset() }
        context?.delete(folder)
        commit()
    }

    /// Waits for the reply under way, if any. For tests.
    func waitForReply() async {
        await streamTask?.value
    }

    /// Waits for the chat's naming request, if any. For tests.
    func waitForTitle() async {
        await titleTask?.value
    }

    /// Clears the screen. A reply still streaming stops, and is saved
    /// stopped with what came so far; its task's own ending then finds
    /// nothing left to change.
    private func leave() {
        if isStreaming, var last = messages.last {
            last.status = .stopped
            save(last)
        }
        streamTask?.cancel()
        streamTask = nil
        messages = []
        chat = nil
        records = [:]
    }

    /// Saves `message` into the open chat, starting the chat with the first
    /// one. Incognito or without a store, does nothing.
    private func save(_ message: ChatMessage) {
        guard let context, !isIncognito else { return }
        let chat = self.chat ?? {
            let chat = Chat(title: ChatTitle.fallback(message.content))
            context.insert(chat)
            self.chat = chat
            return chat
        }()
        let record = records[message.id] ?? {
            let record = Message(id: message.id)
            context.insert(record)
            record.chat = chat
            records[message.id] = record
            return record
        }()
        record.update(from: message)
        if let model = message.model { chat.model = model }
        chat.updatedAt = .now
        chat.lastMessageAt = .now
        commit()
    }

    /// Deletes a stored message: a reply being asked for again.
    private func forget(_ id: UUID) {
        guard let record = records.removeValue(forKey: id) else { return }
        context?.delete(record)
        commit()
    }

    private func commit() {
        do {
            try context?.save()
        } catch {
            print("Error Saving Chats: \(error.localizedDescription)")
        }
    }

    /// What the model sees: the user's messages and the replies that have
    /// text. Failed replies and reasoning stay out.
    nonisolated static func history(_ messages: [ChatMessage]) -> [OllamaChatRequest.Message] {
        messages
            .sorted { $0.sequence < $1.sequence }
            .filter { message in
                switch message.role {
                case .user, .system: true
                case .assistant: message.status != .failed && message.status != .streaming && !message.content.isEmpty
                }
            }
            .map { OllamaChatRequest.Message(role: $0.role.rawValue, content: $0.content) }
    }

    private func reply(client: OllamaClient?, model: OllamaModel?) {
        let history = Self.history(messages)
        let reply = ChatMessage(role: .assistant, sequence: nextSequence, model: model?.name, status: .streaming)
        messages.append(reply)
        // Saved streaming, so a quit mid-reply reopens as stopped and can retry.
        save(reply)
        guard let client else {
            return finish(reply.id, status: .failed, error: "No server is set. Add one in Settings.")
        }
        guard let model else {
            return finish(reply.id, status: .failed, error: "No model is picked. Pick one below.")
        }
        let request = OllamaChatRequest(
            model: model.name,
            messages: history,
            think: model.capabilities?.contains("thinking") == true ? true : nil
        )
        streamTask = Task {
            await stream(reply.id, request: request, client: client)
        }
    }

    private func stream(_ id: UUID, request: OllamaChatRequest, client: OllamaClient) async {
        var request = request
        var content = ""
        var thinking = ""
        var lastShown = Date.distantPast
        func show() {
            update(id) {
                $0.content = content
                $0.thinking = thinking.isEmpty ? nil : thinking
            }
            lastShown = Date()
        }
        while true {
            do {
                var final: OllamaChatChunk?
                for try await chunk in client.chat(request) {
                    content += chunk.message?.content ?? ""
                    thinking += chunk.message?.thinking ?? ""
                    if chunk.done == true { final = chunk }
                    // Redrawing the answer per token is wasted work; 20 a second reads as live.
                    if Date().timeIntervalSince(lastShown) >= 0.05 { show() }
                }
                show()
                if Task.isCancelled { return finish(id, status: .stopped) }
                // A partial answer must never pass for a whole one: the final
                // line has to arrive and say the model stopped.
                guard let final else {
                    return finish(id, status: .failed, error: "The answer was cut off before it finished.")
                }
                update(id) {
                    $0.promptTokens = final.promptEvalCount
                    $0.outputTokens = final.evalCount
                }
                if final.doneReason == "length" {
                    return finish(id, status: .failed, error: "The answer reached the model's length limit and was cut off.")
                }
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return finish(id, status: .failed, error: "No answer came back.")
                }
                finish(id, status: .done)
                return name(client: client, request: request)
            } catch OllamaClient.Failure.http(let status, let message)
                        where status == 400 && request.think != nil && message.localizedCaseInsensitiveContains("does not support thinking") {
                // The model list said it can think; the model disagrees. Ask again without.
                request.think = nil
                content = ""
                thinking = ""
            } catch {
                show()
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    return finish(id, status: .stopped)
                }
                return finish(id, status: .failed, error: Self.describe(error, model: request.model))
            }
        }
    }

    private func finish(_ id: UUID, status: ChatMessage.Status, error: String? = nil) {
        update(id) {
            $0.status = status
            $0.error = error
        }
        if let message = messages.first(where: { $0.id == id }) { save(message) }
    }

    /// Names a saved chat after its first reply, with a separate one-off
    /// request that is never stored as a message. Thinking stays off; the
    /// window matches the chat's, so the model doesn't reload.
    private func name(client: OllamaClient, request: OllamaChatRequest) {
        guard let chat, messages.count == 2, messages[0].role == .user,
              messages[1].role == .assistant, messages[1].status == .done else { return }
        let fallback = ChatTitle.fallback(messages[0].content)
        guard chat.title == fallback else { return }
        let naming = OllamaChatRequest(
            model: request.model,
            messages: [.init(role: "user", content: ChatTitle.prompt(message: messages[0].content, reply: messages[1].content))],
            // Nil for a model that can't think: it rejects even false.
            think: request.think == nil ? nil : false
        )
        titleTask = Task {
            var answer = ""
            do {
                for try await chunk in client.chat(naming) {
                    answer += chunk.message?.content ?? ""
                }
            } catch {
                return print("Error Naming Chat: \(error.localizedDescription)")
            }
            guard let title = ChatTitle.clean(answer) else { return }
            // A rename or delete while the request ran wins.
            guard !chat.isDeleted, chat.modelContext != nil, chat.title == fallback else { return }
            chat.title = title
            chat.updatedAt = .now
            commit()
        }
    }

    /// Changes one message; a no-op once it's gone (a New Session mid-reply).
    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    /// A failed reply's reason, worded for the transcript.
    nonisolated static func describe(_ error: Error, model: String) -> String {
        if let failure = error as? OllamaClient.Failure {
            switch failure {
            case .accessDenied:
                return "Cloudflare Access refused the request. Check the Access Client ID and Secret in Settings."
            case .stream(let message):
                return "Ollama stopped with an error: \(message)"
            case .http(404, let message) where message.localizedCaseInsensitiveContains("not found"):
                return "The server has no model named \(model). Pick another below."
            case .http(524, _):
                return "Ollama took too long to start answering. The model may still be loading; try again in a minute."
            case .http(let status, _) where status == 502 || status == 503 || (520...530).contains(status):
                // Cloudflare's codes for a tunnel or server that isn't there.
                return "Couldn't reach Ollama (\(status)). Check that the server is on and Ollama is running."
            case .http:
                return failure.localizedDescription
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut:
                return "Ollama took too long to answer. The model may still be loading; try again in a minute."
            case .appTransportSecurityRequiresSecureConnection:
                return "The server needs an https:// address. Change it in Settings."
            default:
                return "Couldn't reach Ollama. Check the server address and that the server is on."
            }
        }
        return error.localizedDescription
    }
}
