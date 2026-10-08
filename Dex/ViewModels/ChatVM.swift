//
//  ChatVM.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftData
import UIKit

/// One chat's working copy, and the reply and naming request running for
/// it. Lives on after its chat leaves the screen while a reply streams, so
/// the reply finishes and is saved; then it is dropped, the store holding
/// everything.
@MainActor
private final class ChatSession {
    /// The saved chat; nil until its first message, and always when incognito.
    var chat: Chat?
    let isIncognito: Bool
    var messages: [ChatMessage] = []
    /// The saved chat's stored messages, by id.
    var records: [UUID: Message] = [:]
    var streamTask: Task<Void, Never>?
    var titleTask: Task<Void, Never>?
    /// Saves the streaming reply on a timer, so other devices see it.
    var checkpointTask: Task<Void, Never>?
    /// The reply streaming here, until it finishes.
    var replyID: UUID?

    init(isIncognito: Bool) {
        self.isIncognito = isIncognito
    }

    /// A saved chat, as stored.
    init(_ chat: Chat) {
        self.chat = chat
        isIncognito = false
        let stored = chat.sortedMessages
        records = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        messages = stored.map { ChatMessage($0) }
    }

    /// A reply is streaming here (not on another device).
    var isReplying: Bool {
        replyID != nil
    }
}

/// The chat on screen, and replies still running in chats that left it.
/// `messages` is the screen's working copy; unless incognito, each message
/// is saved when it is sent and when its reply finishes, never per
/// streamed token. Leaving a chat mid-reply lets the reply finish; only an
/// incognito one stops, since nothing of it would be kept.
@MainActor
final class ChatVM: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    /// Incognito chats are never saved.
    @Published var isIncognito: Bool = false
    /// The saved chat on screen; nil until a saved chat's first message.
    @Published private(set) var chat: Chat?
    /// Saved chats with a reply streaming here, on screen or not.
    @Published private(set) var streamingChatIDs: Set<UUID> = []
    /// Where chats are saved; nil keeps everything in memory (previews).
    var context: ModelContext?

    /// The chat on screen; nil for a new chat before its first message.
    private var current: ChatSession?
    /// Chats left mid-reply, until their replies finish.
    private var background: [ChatSession] = []
    /// Keeps a reply going for a while after the app leaves the screen.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// The chat on screen has a reply coming, here or on another device:
    /// nothing can be sent until it finishes.
    var isStreaming: Bool {
        messages.last?.status == .streaming
    }

    /// The reply coming is streaming here, so Stop can end it.
    var isReplyingHere: Bool {
        current?.isReplying ?? false
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

    /// After every message in the session and every stored one: another
    /// device may have added to the chat since it opened, and a repeated
    /// number would mix the two orders on the next open.
    private func nextSequence(_ session: ChatSession) -> Int {
        let stored = session.chat?.messages?.map(\.sequence) ?? []
        return ((session.messages.map(\.sequence) + stored).max() ?? -1) + 1
    }

    /// Whether the last reply can be asked for again.
    var canRetry: Bool {
        guard let last = messages.last else { return false }
        return last.role == .assistant && (last.status == .failed || last.status == .stopped)
    }

    func send(_ text: String, client: OllamaClient?, model: OllamaModel?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        let session = current ?? ChatSession(isIncognito: isIncognito)
        current = session
        let message = ChatMessage(role: .user, content: text, sequence: nextSequence(session))
        session.messages.append(message)
        save(message, in: session)
        publish(session)
        reply(in: session, client: client, model: model)
    }

    /// Replaces the last failed or stopped reply with a new one.
    func retry(client: OllamaClient?, model: OllamaModel?) {
        guard canRetry, let session = current else { return }
        forget(session.messages.removeLast().id, in: session)
        publish(session)
        reply(in: session, client: client, model: model)
    }

    /// Ends the reply on screen where it is; what streamed so far stays.
    func stop() {
        current?.streamTask?.cancel()
    }

    /// A new, empty chat.
    func reset() {
        leave()
        isIncognito = false
    }

    /// Puts a saved chat on screen; one still replying picks up live.
    func open(_ chat: Chat) {
        guard chat !== self.chat else { return }
        leave()
        isIncognito = false
        if let index = background.firstIndex(where: { $0.chat === chat }) {
            current = background.remove(at: index)
        } else {
            let session = ChatSession(chat)
            current = session
            settleCutOffReplies(in: session)
        }
        publish(current)
    }

    /// Takes in what reached the store since the chat opened: another
    /// device's messages, replies it finished, a reply it retried away. A
    /// reply streaming here keeps its own copy; the store has only its start.
    func refresh() {
        guard let session = current, let chat = session.chat else { return }
        guard !chat.isDeleted, chat.modelContext != nil else { return reset() }
        let stored = chat.sortedMessages
        session.records = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        settleCutOffReplies(in: session)
        let merged = Self.merge(local: session.messages, stored: stored.map { ChatMessage($0) }, replyID: session.replyID)
        // Unchanged after this device's own saves: no redraw.
        if merged != session.messages {
            session.messages = merged
            publish(session)
        }
    }

    /// The stored messages, in order, but the reply streaming here (`replyID`)
    /// as it is here, kept even if the store lost it (another device retried
    /// it away): it is saved again when it finishes. A reply streaming on
    /// another device takes each checkpoint from the store.
    nonisolated static func merge(local: [ChatMessage], stored: [ChatMessage], replyID: UUID?) -> [ChatMessage] {
        let streaming = local.filter { $0.id == replyID }
        return (stored.filter { $0.id != replyID } + streaming)
            .sorted { $0.sequence < $1.sequence }
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

    /// Deletes a saved chat, and its messages; an empty chat replaces it on
    /// screen, and a reply still running for it stops.
    func delete(_ chat: Chat) {
        if chat === self.chat { reset() }
        drop { $0.chat === chat }
        context?.delete(chat)
        commit()
    }

    /// Deletes a folder and every chat in it; if one of them is on screen,
    /// an empty chat replaces it, and replies still running in them stop.
    func delete(_ folder: Folder) {
        if let chat, chat.folder === folder { reset() }
        drop { $0.chat?.folder === folder }
        context?.delete(folder)
        commit()
    }

    /// Pins a saved chat, or unpins a pinned one.
    func togglePin(_ chat: Chat) {
        chat.pinnedAt = chat.pinnedAt == nil ? .now : nil
        commit()
    }

    /// Pins a folder, or unpins a pinned one.
    func togglePin(_ folder: Folder) {
        folder.pinnedAt = folder.pinnedAt == nil ? .now : nil
        commit()
    }

    /// Saves the pinned rows' order, top first, as their pin times: the top
    /// row the latest, each next a second earlier, so a new pin still
    /// lands on top.
    func reorderPinned(_ items: [DrawerItem], now: Date = .now) {
        guard let context else { return }
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let chats = (try? context.fetch(FetchDescriptor<Chat>())) ?? []
        for (index, item) in items.enumerated() {
            let pinnedAt = now.addingTimeInterval(-Double(index))
            if item.kind == .folder {
                folders.first { $0.id.uuidString == item.id }?.pinnedAt = pinnedAt
            } else {
                chats.first { $0.id.uuidString == item.id }?.pinnedAt = pinnedAt
            }
        }
        commit()
    }

    /// Waits for every reply under way, on screen or not. For tests.
    func waitForReply() async {
        for task in ([current] + background).compactMap({ $0?.streamTask }) {
            await task.value
        }
    }

    /// Waits for the chat on screen's naming request, if any. For tests.
    func waitForTitle() async {
        await current?.titleTask?.value
    }

    /// Clears the screen. A saved chat's reply keeps going; an incognito
    /// one stops, saved nowhere.
    private func leave() {
        guard let session = current else { return }
        current = nil
        if session.isReplying {
            if session.chat == nil {
                session.streamTask?.cancel()
            } else {
                background.append(session)
            }
        }
        publish(nil)
    }

    /// Saves replies stored streaming but no longer coming as stopped, so
    /// they stay that way: a later save or sync can't bring them back.
    private func settleCutOffReplies(in session: ChatSession) {
        let cutOff = session.records.values.filter {
            $0.status == ChatMessage.Status.streaming.rawValue && $0.id != session.replyID && !$0.isLiveElsewhere()
        }
        guard !cutOff.isEmpty else { return }
        for record in cutOff {
            record.status = ChatMessage.Status.stopped.rawValue
            record.checkpointAt = nil
            record.replyDevice = nil
        }
        commit()
    }

    /// Stops the replies of chats being deleted, and forgets them.
    private func drop(where isGone: (ChatSession) -> Bool) {
        for session in background where isGone(session) {
            session.streamTask?.cancel()
            session.checkpointTask?.cancel()
            session.titleTask?.cancel()
        }
        background.removeAll(where: isGone)
        publish(nil)
    }

    /// Shows `session` if it's the one on screen (nil: the screen just
    /// changed), and updates which chats are replying.
    private func publish(_ session: ChatSession?) {
        if session === current {
            if messages != (current?.messages ?? []) { messages = current?.messages ?? [] }
            if chat !== current?.chat { chat = current?.chat }
        }
        let sessions = ([current] + background).compactMap { $0 }
        let ids = Set(sessions.filter(\.isReplying).compactMap { $0.chat?.id })
        if ids != streamingChatIDs { streamingChatIDs = ids }
        holdForBackground(sessions.contains(where: \.isReplying))
    }

    /// While any reply streams, asks iOS for time to finish it if the app
    /// leaves the screen; iOS gives a few seconds to minutes, not forever.
    /// Asked only while active: once time runs out in the background, a
    /// reply still streaming must not ask again on every token.
    private func holdForBackground(_ isReplying: Bool) {
        if isReplying, backgroundTask == .invalid, UIApplication.shared.applicationState == .active {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Reply") { [weak self] in
                // Ended before returning, or iOS ends the app.
                MainActor.assumeIsolated { self?.endBackgroundTask() }
            }
        } else if !isReplying {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Saves `message` into the session's chat, starting the chat with the
    /// first one. Incognito, without a store, or once the chat is deleted,
    /// does nothing.
    private func save(_ message: ChatMessage, in session: ChatSession) {
        guard let context, !session.isIncognito else { return }
        if let chat = session.chat, chat.isDeleted || chat.modelContext == nil { return }
        let chat = session.chat ?? {
            let chat = Chat(title: ChatTitle.fallback(message.content))
            context.insert(chat)
            session.chat = chat
            return chat
        }()
        // Gone from the store (another device retried it away): saved anew.
        if let record = session.records[message.id], record.isDeleted || record.modelContext == nil {
            session.records[message.id] = nil
        }
        let record = session.records[message.id] ?? {
            let record = Message(id: message.id)
            context.insert(record)
            record.chat = chat
            session.records[message.id] = record
            return record
        }()
        record.update(from: message)
        let isStreaming = message.status == .streaming
        record.checkpointAt = isStreaming ? .now : nil
        record.replyDevice = isStreaming ? Message.thisDevice : nil
        if let model = message.model { chat.model = model }
        chat.updatedAt = .now
        chat.lastMessageAt = .now
        commit()
    }

    /// Deletes a stored message: a reply being asked for again.
    private func forget(_ id: UUID, in session: ChatSession) {
        guard let record = session.records.removeValue(forKey: id) else { return }
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

    private func reply(in session: ChatSession, client: OllamaClient?, model: OllamaModel?) {
        let history = Self.history(session.messages)
        let reply = ChatMessage(role: .assistant, sequence: nextSequence(session), model: model?.name, status: .streaming)
        session.messages.append(reply)
        session.replyID = reply.id
        // Saved streaming, so a quit mid-reply reopens as stopped and can retry.
        save(reply, in: session)
        publish(session)
        guard let client else {
            return finish(reply.id, in: session, status: .failed, error: "No server is set. Add one in Settings.")
        }
        guard let model else {
            return finish(reply.id, in: session, status: .failed, error: "No model is picked. Pick one below.")
        }
        let request = OllamaChatRequest(
            model: model.name,
            messages: history,
            think: model.capabilities?.contains("thinking") == true ? true : nil
        )
        session.streamTask = Task {
            await stream(reply.id, in: session, request: request, client: client)
        }
        session.checkpointTask = Task {
            await checkpoint(reply.id, in: session)
        }
    }

    private func stream(_ id: UUID, in session: ChatSession, request: OllamaChatRequest, client: OllamaClient) async {
        var request = request
        var content = ""
        var thinking = ""
        var lastShown = Date.distantPast
        func show() {
            update(id, in: session) {
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
                if Task.isCancelled { return finish(id, in: session, status: .stopped) }
                // A partial answer must never pass for a whole one: the final
                // line has to arrive and say the model stopped.
                guard let final else {
                    return finish(id, in: session, status: .failed, error: "The answer was cut off before it finished.")
                }
                update(id, in: session) {
                    $0.promptTokens = final.promptEvalCount
                    $0.outputTokens = final.evalCount
                }
                if final.doneReason == "length" {
                    return finish(id, in: session, status: .failed, error: "The answer reached the model's length limit and was cut off.")
                }
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return finish(id, in: session, status: .failed, error: "No answer came back.")
                }
                finish(id, in: session, status: .done)
                return name(in: session, client: client, request: request)
            } catch OllamaClient.Failure.http(let status, let message)
                        where status == 400 && request.think != nil && message.localizedCaseInsensitiveContains("does not support thinking") {
                // The model list said it can think; the model disagrees. Ask again without.
                request.think = nil
                content = ""
                thinking = ""
            } catch {
                show()
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    return finish(id, in: session, status: .stopped)
                }
                return finish(id, in: session, status: .failed, error: Self.describe(error, model: request.model))
            }
        }
    }

    /// Saves a streaming reply as it stands every few seconds, tokens or
    /// not (a model still loading sends none), so other devices see it come
    /// in and know it's alive.
    private func checkpoint(_ id: UUID, in session: ChatSession) async {
        while session.replyID == id {
            try? await Task.sleep(for: .seconds(Message.checkpointInterval))
            guard !Task.isCancelled, session.replyID == id,
                  let message = session.messages.first(where: { $0.id == id }) else { return }
            save(message, in: session)
        }
    }

    /// Ends a reply and saves it. A chat that left the screen is then done
    /// with: the store has it all.
    private func finish(_ id: UUID, in session: ChatSession, status: ChatMessage.Status, error: String? = nil) {
        update(id, in: session) {
            $0.status = status
            $0.error = error
        }
        if session.replyID == id {
            session.replyID = nil
            session.checkpointTask?.cancel()
        }
        if let message = session.messages.first(where: { $0.id == id }) { save(message, in: session) }
        background.removeAll { $0 === session }
        publish(session)
    }

    /// Names a saved chat after its first reply, with a separate one-off
    /// request that is never stored as a message. Thinking stays off; the
    /// window matches the chat's, so the model doesn't reload.
    private func name(in session: ChatSession, client: OllamaClient, request: OllamaChatRequest) {
        let messages = session.messages
        guard let chat = session.chat, messages.count == 2, messages[0].role == .user,
              messages[1].role == .assistant, messages[1].status == .done else { return }
        let fallback = ChatTitle.fallback(messages[0].content)
        guard chat.title == fallback else { return }
        let naming = OllamaChatRequest(
            model: request.model,
            messages: [.init(role: "user", content: ChatTitle.prompt(message: messages[0].content, reply: messages[1].content))],
            // Nil for a model that can't think: it rejects even false.
            think: request.think == nil ? nil : false
        )
        session.titleTask = Task {
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

    /// Changes one message of a session, showing it if on screen; a no-op
    /// once it's gone (retried away).
    private func update(_ id: UUID, in session: ChatSession, _ change: (inout ChatMessage) -> Void) {
        guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&session.messages[index])
        publish(session)
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
