//
//  ChatVM.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftData
import SwiftUI

/// One chat's working copy, and the reply running for it. Lives on after
/// its chat leaves the screen while a reply streams, so the reply finishes
/// and is saved; then it is dropped, the store holding everything.
@MainActor
private final class ChatSession {
    /// The saved chat; nil until the server takes its first message, and
    /// always when incognito.
    var chat: Chat?
    let isIncognito: Bool
    var messages: [ChatMessage] = []
    /// The saved chat's stored messages, by id.
    var records: [String: Message] = [:]
    /// Starting the reply, then (if the live channel dropped) following it.
    var task: Task<Void, Never>?
    /// The reply is being started: the server hasn't taken it yet.
    var isStarting = false
    /// Messages the server doesn't have yet: a question and its reply until
    /// the server takes them; kept, if it never did, for Retry.
    var unsent: Set<String> = []
    /// The folder and title a new chat is saved with, fixed when its first
    /// message is sent.
    var folder: Folder?
    var title: String?
    /// The reply coming, until it finishes.
    var replyID: String?
    /// The reply as built so far from the live channel.
    var parts = ReplyParts()
    /// When the reply was last redrawn.
    var lastShown = Date.distantPast
    /// The live channel carries the reply; false once it dropped, when the
    /// saved chat is read instead.
    var isLive = false
    /// The server the reply runs on.
    var server: ReplyServer?
    /// The chat's id for the server: a saved chat's own, or an incognito
    /// one's temporary id.
    var serverChatID: String?

    init(isIncognito: Bool) {
        self.isIncognito = isIncognito
    }

    /// A saved chat, as stored.
    init(_ chat: Chat) {
        self.chat = chat
        isIncognito = false
        serverChatID = chat.id
        let stored = chat.sortedMessages
        records = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        messages = stored.map { ChatMessage($0) }
    }

    var isReplying: Bool {
        replyID != nil
    }
}

/// The chat on screen, and replies still running in chats that left it.
/// Replies run on the server as jobs: they finish and are saved there even
/// if Dex closes. While Dex is open they stream over the live channel;
/// otherwise the saved chat is read until they finish.
@MainActor
final class ChatVM: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    /// Incognito chats are never saved.
    @Published var isIncognito: Bool = false
    /// The saved chat on screen; nil until a saved chat's first message.
    @Published private(set) var chat: Chat?
    /// Saved chats with a reply coming, on screen or not.
    @Published private(set) var streamingChatIDs: Set<String> = []
    /// Where chats are saved; nil keeps everything in memory (previews).
    var context: ModelContext?
    /// The server replies run on; nil while none is set up.
    var server: ReplyServer? {
        didSet {
            server?.onEvent = { [weak self] event in self?.handle(event) }
        }
    }

    /// The chat on screen; nil for a new chat before its first message.
    private var current: ChatSession?
    /// Chats left mid-reply, until their replies finish.
    private var background: [ChatSession] = []
    /// The folder a new chat joins with its first message: one started from
    /// a folder's page. Shown in its chip before then.
    @Published private(set) var newChatFolder: Folder?
    /// How often a reply not on the live channel is read from the server.
    var followInterval: Duration = .milliseconds(1500)

    /// The chat on screen has a reply coming, or one being started: nothing
    /// can be sent until it finishes.
    var isStreaming: Bool {
        messages.last?.status == .streaming || isStarting
    }

    /// The chat on screen's reply is being started; the server hasn't taken it.
    @Published private(set) var isStarting = false

    /// The reply coming can be stopped from here.
    var isReplyingHere: Bool {
        current?.isReplying ?? false
    }

    /// Tokens the chat fills, against `WebUIReplyRequest.contextLength`.
    var contextUsed: Int? {
        Self.contextUsed(messages)
    }

    /// The last finished reply's prompt plus output. A prompt carries the
    /// whole chat, so it can't be smaller than the reply before it; when the
    /// server reports less (it may count only what it didn't have cached),
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

    /// After every message in the session and every stored one: a repeated
    /// number would mix the two orders on the next open.
    private func nextSequence(_ session: ChatSession) -> Int {
        let stored = session.chat?.messages.map(\.sequence) ?? []
        return ((session.messages.map(\.sequence) + stored).max() ?? -1) + 1
    }

    /// Whether the last reply can be asked for again.
    var canRetry: Bool {
        guard let last = messages.last else { return false }
        return last.role == .assistant && (last.status == .failed || last.status == .stopped)
    }

    /// Sends `text` and asks `model` for a reply, which may search the web
    /// when `webSearch` is on.
    func send(_ text: String, model: String?, webSearch: Bool = true) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        let session = current ?? {
            let session = ChatSession(isIncognito: isIncognito)
            if !isIncognito { session.folder = newChatFolder }
            session.title = ChatTitle.fallback(text)
            return session
        }()
        current = session
        // After the last message the server has: one it never took isn't a parent.
        let parent = session.messages.lastIndex { !session.unsent.contains($0.id) }
        let message = ChatMessage(role: .user, content: text, sequence: nextSequence(session),
                                  parentId: parent.map { session.messages[$0].id })
        if let parent {
            session.messages[parent].childrenIds.append(message.id)
        }
        session.messages.append(message)
        publish(session)
        reply(to: message.id, in: session, model: model, webSearch: webSearch)
    }

    /// Asks again for the last failed or stopped reply. The old one stays on
    /// the server, a sibling of the new; Dex shows the new one.
    func retry(model: String?, webSearch: Bool = true) {
        guard canRetry, let session = current, let question = session.messages.dropLast().last else { return }
        forget(session.messages.removeLast().id, in: session)
        publish(session)
        reply(to: question.id, in: session, model: model, webSearch: webSearch)
    }

    /// Ends the reply on screen where it is; what streamed so far stays,
    /// on the server too.
    func stop() {
        guard let session = current, let id = session.replyID else { return }
        // Still starting: `start` stops the job once the server names its chat.
        if !session.isStarting {
            session.task?.cancel()
            session.task = nil
        }
        // Shows what streamed since the last redraw, too.
        finish(id, in: session, status: .stopped)
        if !session.isStarting { stopOnServer(id, in: session) }
    }

    /// Stops a reply's job and saves what showed of it, marked stopped: the
    /// server keeps nothing of a stopped reply.
    private func stopOnServer(_ id: String, in session: ChatSession) {
        guard let server = session.server, let chatID = session.serverChatID else { return }
        let content = session.messages.first { $0.id == id }?.content ?? ""
        let isSaved = session.chat != nil
        Task {
            try? await server.client.stopReply(chat: chatID)
            if isSaved { try? await server.client.save(reply: id, chat: chatID, content: content) }
        }
    }

    /// A new, empty chat; started from a folder's page, it joins `folder`
    /// with its first message, so an abandoned one never lands there.
    func reset(into folder: Folder? = nil) {
        leave()
        isIncognito = false
        newChatFolder = folder
    }

    /// Moves a saved chat into `folder`, or out of any with nil. Its place
    /// in Chats stays.
    func move(_ chat: Chat, to folder: Folder?) {
        guard chat.folder !== folder else { return }
        chat.folder = folder
        commit()
    }

    /// Puts a saved chat on screen; one still replying picks up live. The
    /// server's copy then replaces the stored one if it changed.
    func open(_ chat: Chat) {
        guard chat !== self.chat else { return }
        leave()
        isIncognito = false
        newChatFolder = nil
        if let index = background.firstIndex(where: { $0.chat === chat }) {
            current = background.remove(at: index)
        } else {
            let session = ChatSession(chat)
            current = session
            if let reply = session.messages.last, reply.role == .assistant, reply.status == .streaming {
                // Running on the server, or cut off: the server says which.
                session.replyID = reply.id
                follow(session)
            }
            sync(session)
        }
        markRead(current)
        publish(current)
    }

    /// Takes in what reached the store since the chat opened. A reply
    /// streaming here keeps its own copy.
    func refresh() {
        guard let session = current, let chat = session.chat else { return }
        guard !chat.isDeleted, chat.modelContext != nil else { return reset() }
        let stored = chat.sortedMessages
        session.records = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = Self.merge(local: session.messages, stored: stored.map { ChatMessage($0) }, replyID: session.replyID)
        // Unchanged after this device's own saves: no redraw.
        if merged != session.messages {
            session.messages = merged
            publish(session)
        }
    }

    /// The stored messages, in order, but the reply streaming here (`replyID`)
    /// as it is here, kept even if the store lost it: it is saved again when
    /// it finishes.
    nonisolated static func merge(local: [ChatMessage], stored: [ChatMessage], replyID: String?) -> [ChatMessage] {
        let streaming = local.filter { $0.id == replyID }
        return (stored.filter { $0.id != replyID } + streaming)
            .sorted { $0.sequence < $1.sequence }
    }

    /// Renames a saved chat. A blank name changes nothing; a rename made
    /// while the chat is being named wins over the server's name.
    func rename(_ chat: Chat, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != chat.title else { return }
        chat.title = title
        commit()
        onServer { try await $0.rename(chat: chat.id, to: title) }
    }

    /// Deletes a saved chat, and its messages; an empty chat replaces it on
    /// screen, and a reply still running for it is let go.
    func delete(_ chat: Chat) {
        if chat === self.chat { reset() }
        drop { $0.chat === chat }
        let id = chat.id
        context?.delete(chat)
        commit()
        onServer { try await $0.delete(chat: id) }
    }

    /// Deletes a folder and every chat in it; if one of them is on screen,
    /// an empty chat replaces it, and replies still running in them are let go.
    func delete(_ folder: Folder) {
        if let chat, chat.folder === folder { reset() }
        drop { $0.chat?.folder === folder }
        // As the server does: a folder's chats go with it.
        let ids = folder.chats.map(\.id)
        for chat in folder.chats { context?.delete(chat) }
        context?.delete(folder)
        commit()
        // Folders reach the server in stage 4; their chats already do.
        for id in ids { onServer { try await $0.delete(chat: id) } }
    }

    /// Pins a saved chat, or unpins a pinned one.
    func togglePin(_ chat: Chat) {
        chat.pinnedAt = chat.pinnedAt == nil ? .now : nil
        commit()
        let id = chat.id
        let pinned = chat.pinnedAt != nil
        // The server only flips; flip again if it was already as asked.
        onServer { client in
            if try await client.togglePin(chat: id) != pinned { _ = try await client.togglePin(chat: id) }
        }
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
                folders.first { $0.id == item.id }?.pinnedAt = pinnedAt
            } else {
                chats.first { $0.id == item.id }?.pinnedAt = pinnedAt
            }
        }
        commit()
    }

    /// Back on screen after the app was away: replies whose live channel
    /// dropped meanwhile are read from the server until they finish, and the
    /// chat on screen catches up with it.
    func resume() {
        for session in ([current] + background).compactMap({ $0 }) where session.isReplying && !session.isLive {
            if session.task == nil { follow(session) }
        }
        if let current { sync(current) }
    }

    /// Waits for every reply under way, on screen or not. For tests.
    func waitForReply() async {
        while let task = ([current] + background).compactMap({ $0?.task }).first {
            await task.value
            // A reply that lost its channel goes on in a new task.
            if ([current] + background).compactMap({ $0?.task }).first == task { break }
        }
    }

    // MARK: Replies

    /// Asks for a reply to the user message `questionID`.
    private func reply(to questionID: String, in session: ChatSession, model: String?, webSearch: Bool) {
        let reply = ChatMessage(role: .assistant, sequence: nextSequence(session), model: model, status: .streaming,
                                parentId: questionID)
        session.messages.append(reply)
        // Every earlier reply stays listed: the server keeps them as siblings.
        if let index = session.messages.firstIndex(where: { $0.id == questionID }) {
            session.messages[index].childrenIds.append(reply.id)
        }
        session.replyID = reply.id
        session.parts = ReplyParts()
        session.unsent.formUnion([questionID, reply.id])
        publish(session)
        guard let server else {
            return finish(reply.id, in: session, status: .failed, error: "No server is set. Add one in Settings.")
        }
        guard let model else {
            return finish(reply.id, in: session, status: .failed, error: "No model is picked. Pick one below.")
        }
        session.server = server
        session.isStarting = true
        publish(session)
        session.task = Task {
            await start(reply.id, question: questionID, in: session, server: server, model: model, webSearch: webSearch)
        }
    }

    /// Starts the reply as a server job; the live channel brings the rest.
    /// A new saved chat is stored once the server has named its id.
    private func start(_ id: String, question questionID: String, in session: ChatSession, server: ReplyServer,
                       model: String, webSearch: Bool) async {
        defer {
            session.isStarting = false
            publish(session)
        }
        guard let question = session.messages.first(where: { $0.id == questionID }) else { return }
        do {
            let sid = try await server.sessionID()
            guard session.replyID == id else { return }
            session.isLive = true
            let isNew = session.serverChatID == nil
            if session.isIncognito { session.serverChatID = WebUIReplyRequest.temporaryChatID(sessionID: sid) }
            var request = WebUIReplyRequest(
                model: model, sessionID: sid, id: id, chatID: session.serverChatID, parentID: question.parentId,
                userMessage: .init(id: question.id, parentId: question.parentId, childrenIds: question.childrenIds,
                                   content: question.content, timestamp: Int(question.createdAt.timeIntervalSince1970),
                                   models: [model]))
            request.features.webSearch = webSearch
            // A saved chat's history is on the server; a new or incognito one
            // brings its own.
            if isNew || session.isIncognito { request.messages = Self.history(session.messages, upTo: questionID) }
            if isNew && !session.isIncognito { request.backgroundTasks = .init() }
            let chatID = try await server.client.startReply(request)
            session.isStarting = false
            session.task = nil
            session.unsent.subtract([questionID, id])
            // Kept even if the reply ended meanwhile (it finished fast, or was
            // stopped): the chat exists on the server now.
            if !session.isIncognito {
                session.serverChatID = chatID
                // The question, its reply, and the message before it, which now lists the question.
                let saving = [question.parentId, questionID, id].compactMap { $0 }
                for message in session.messages where saving.contains(message.id) {
                    save(message, in: session)
                }
            }
            if session.messages.first(where: { $0.id == id })?.status == .stopped {
                stopOnServer(id, in: session)
            } else if session.replyID == id && !session.isLive {
                // The live channel dropped while this was out.
                follow(session)
            }
        } catch {
            session.task = nil
            guard !Task.isCancelled, !(error is CancellationError), session.replyID == id else { return }
            finish(id, in: session, status: .failed, error: Self.describe(error, model: model))
        }
    }

    /// What a new or incognito chat sends as its history: every message up
    /// to and including the question, but replies that failed or have no text.
    nonisolated static func history(_ messages: [ChatMessage], upTo questionID: String) -> [[String: String]] {
        var history: [[String: String]] = []
        for message in messages.sorted(by: { $0.sequence < $1.sequence }) {
            let keep = switch message.role {
            case .user, .system: true
            case .assistant: message.status != .failed && message.status != .streaming && !message.content.isEmpty
            }
            if keep { history.append(["role": message.role.rawValue, "content": message.content]) }
            if message.id == questionID { break }
        }
        return history
    }

    /// One event from the live channel, for whichever chat it belongs to.
    private func handle(_ event: WebUIEvent) {
        let sessions = ([current] + background).compactMap { $0 }
        func replying(_ messageID: String) -> ChatSession? {
            sessions.first { $0.replyID == messageID && $0.isLive }
        }
        switch event {
        case .text(_, let messageID, let delta):
            guard let session = replying(messageID) else { return }
            session.parts.appendText(delta)
            show(messageID, in: session)
        case .reasoning(_, let messageID, let itemID, let delta):
            guard let session = replying(messageID) else { return }
            session.parts.appendThought(delta, itemID: itemID)
            show(messageID, in: session)
        case .item(_, let messageID, let item, let isDone):
            guard let session = replying(messageID) else { return }
            session.parts.apply(item, isDone: isDone)
            // Steps are few, and a lookup row should show at once.
            show(messageID, in: session, now: true)
        case .finished(_, let messageID, let output, let usage):
            guard let session = replying(messageID) else { return }
            let parts = ReplyParts(output: output, fallback: session.parts.content)
            session.parts = parts
            update(messageID, in: session) {
                Self.apply(parts, to: &$0)
                $0.promptTokens = usage?.promptTokens
                $0.outputTokens = usage?.completionTokens
            }
            if parts.content.isEmpty {
                return finish(messageID, in: session, status: .failed, error: "No answer came back.")
            }
            finish(messageID, in: session, status: .done)
        case .failed(_, let messageID, let message):
            guard let session = replying(messageID) else { return }
            finish(messageID, in: session, status: .failed, error: message)
        case .title(let chatID, let title):
            name(chatID, title)
        case .disconnected:
            // The rest of each reply is read from the server instead.
            for session in sessions where session.isReplying && session.isLive {
                session.isLive = false
                if session.task == nil { follow(session) }
            }
        case .tags, .active, .listChanged:
            break
        }
    }

    /// The server named a saved chat. A rename made meanwhile wins.
    private func name(_ chatID: String, _ title: String) {
        let title = ChatTitle.clean(title) ?? title
        guard let context, let chat = try? context.fetch(FetchDescriptor<Chat>(predicate: #Predicate { $0.id == chatID })).first,
              let first = chat.sortedMessages.first, chat.title == ChatTitle.fallback(first.content) else { return }
        chat.title = title
        commit()
    }

    /// Reads a reply that isn't on the live channel from the saved chat
    /// until it finishes. A reply the server has no job for and never
    /// finished was cut off: it stops.
    private func follow(_ session: ChatSession) {
        guard let id = session.replyID else { return }
        // The server the reply started on, even if Settings changed since.
        guard let server = session.server ?? server, let chatID = session.serverChatID, session.chat != nil else {
            // Nothing to read it from: an incognito reply is gone with its channel.
            return finish(id, in: session, status: .stopped)
        }
        session.server = server
        session.task = Task {
            while !Task.isCancelled, session.replyID == id, !session.isLive {
                do {
                    let remote = try await server.client.chat(id: chatID)
                    guard !Task.isCancelled, session.replyID == id else { return }
                    if let message = remote.chat.history.messages[id] {
                        let fresh = CacheSync.message(message, sequence: 0)
                        update(id, in: session) {
                            $0.content = fresh.content
                            $0.thinking = fresh.thinking
                            $0.lookups = fresh.lookups
                            $0.promptTokens = fresh.promptTokens
                            $0.outputTokens = fresh.outputTokens
                        }
                        if fresh.status != .streaming {
                            session.task = nil
                            return finish(id, in: session, status: fresh.status, error: fresh.error)
                        }
                    }
                    if try await server.client.tasks(chat: chatID).isEmpty {
                        // Recheck: it may have finished between the two reads.
                        let again = try await server.client.chat(id: chatID).chat.history.messages[id]
                        guard session.replyID == id else { return }
                        let status = again.map { CacheSync.message($0, sequence: 0).status } ?? .stopped
                        session.task = nil
                        return finish(id, in: session, status: status == .streaming ? .stopped : status)
                    }
                } catch WebUIClient.Failure.notFound {
                    session.task = nil
                    return finish(id, in: session, status: .stopped)
                } catch {
                    // Offline for now: try again on the next round.
                }
                try? await Task.sleep(for: followInterval)
            }
            session.task = nil
        }
    }

    /// Replaces a saved chat's stored messages with the server's, if they
    /// changed, unless a reply is coming here.
    private func sync(_ session: ChatSession) {
        guard let server, let chat = session.chat, let context else { return }
        let chatID = chat.id
        Task {
            guard let remote = try? await server.client.chat(id: chatID) else { return }
            guard !chat.isDeleted, chat.modelContext != nil else { return }
            // Renamed or pinned elsewhere: the messages stand, the details change.
            CacheSync.storeDetails(remote, into: chat)
            commit()
            guard !session.isReplying,
                  chat.messagesSyncedAt.map({ $0.timeIntervalSince1970 < TimeInterval(remote.updatedAt) }) ?? true
            else { return }
            CacheSync.store(remote, into: chat, context: context)
            commit()
            session.records = Dictionary(chat.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            session.messages = chat.sortedMessages.map { ChatMessage($0) }
            if let reply = session.messages.last, reply.role == .assistant, reply.status == .streaming {
                session.replyID = reply.id
                follow(session)
            }
            // On screen, what came in is read.
            if session === current { markRead(session) }
            publish(session)
        }
    }

    private static func apply(_ parts: ReplyParts, to message: inout ChatMessage) {
        message.content = parts.content
        message.thinking = parts.thinking
        message.lookups = parts.lookups.isEmpty ? nil : parts.lookups
    }

    /// Shows the reply as built so far, at most 20 times a second unless
    /// `now`: redrawing per token is wasted work. `finish` shows the rest.
    private func show(_ id: String, in session: ChatSession, now: Bool = false) {
        guard now || Date().timeIntervalSince(session.lastShown) >= 0.05,
              let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
        Self.apply(session.parts, to: &session.messages[index])
        session.lastShown = Date()
        publish(session)
    }

    /// Ends a reply and saves it. A chat that left the screen is then done
    /// with: the store has it all.
    private func finish(_ id: String, in session: ChatSession, status: ChatMessage.Status, error: String? = nil) {
        // What streamed since the last redraw.
        let parts = session.isLive && status != .done ? session.parts : nil
        update(id, in: session) {
            if let parts, parts.content.count >= $0.content.count { Self.apply(parts, to: &$0) }
            $0.status = status
            $0.error = error
            // A lookup still running when the reply ended didn't finish.
            $0.lookups = $0.lookups?.map { lookup in
                var lookup = lookup
                if lookup.state == .running { lookup.state = .failed }
                return lookup
            }
        }
        if session.replyID == id {
            session.replyID = nil
            session.isLive = false
        }
        if let message = session.messages.first(where: { $0.id == id }) { save(message, in: session) }
        background.removeAll { $0 === session }
        if session === current { markRead(session) }
        publish(session)
    }

    /// A chat on screen is read, here and on the server.
    private func markRead(_ session: ChatSession?) {
        guard let chat = session?.chat else { return }
        chat.lastReadAt = chat.updatedAt
        server?.markRead(chatID: chat.id)
    }

    // MARK: Screen and store

    /// Clears the screen. A saved chat's reply keeps going; an incognito
    /// one stops, saved nowhere.
    private func leave() {
        guard let session = current else { return }
        current = nil
        if session.isReplying {
            if session.chat == nil && session.isIncognito {
                stopIncognito(session)
            } else {
                background.append(session)
            }
        }
        publish(nil)
    }

    private func stopIncognito(_ session: ChatSession) {
        session.task?.cancel()
        if let server = session.server, let chatID = session.serverChatID {
            Task { try? await server.client.stopReply(chat: chatID) }
        }
        session.replyID = nil
    }

    /// Lets go of the replies of chats being deleted.
    private func drop(where isGone: (ChatSession) -> Bool) {
        for session in background where isGone(session) {
            session.task?.cancel()
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
        let starting = current?.isStarting ?? false
        if starting != isStarting { isStarting = starting }
        let sessions = ([current] + background).compactMap { $0 }
        let ids = Set(sessions.filter(\.isReplying).compactMap { $0.chat?.id })
        if ids != streamingChatIDs { streamingChatIDs = ids }
    }

    /// Saves `message` into the session's chat, starting the chat, under the
    /// server's id, with the first one. Incognito, without a store, once the
    /// chat is deleted, or for a message the server doesn't have, does nothing.
    private func save(_ message: ChatMessage, in session: ChatSession) {
        // The cache holds what the server has: an exchange it never took
        // stays on screen, for Retry, but isn't stored.
        guard let context, !session.isIncognito, let chatID = session.serverChatID,
              !session.unsent.contains(message.id) else { return }
        if let chat = session.chat, chat.isDeleted || chat.modelContext == nil { return }
        let chat = session.chat ?? {
            let chat = Chat(id: chatID, title: session.title ?? ChatTitle.fallback(message.content))
            context.insert(chat)
            if let folder = session.folder, !folder.isDeleted, folder.modelContext != nil {
                chat.folder = folder
            }
            if newChatFolder === session.folder { newChatFolder = nil }
            session.chat = chat
            return chat
        }()
        // Gone from the store: saved anew.
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
        if let model = message.model { chat.model = model }
        chat.updatedAt = .now
        // Read as it arrives: a chat's own messages never mark it unread.
        chat.lastReadAt = chat.updatedAt
        commit()
        publish(session)
    }

    /// Deletes a stored reply being asked for again. Its question still
    /// lists it: the server keeps it as a sibling of the new one.
    private func forget(_ id: String, in session: ChatSession) {
        guard let record = session.records.removeValue(forKey: id) else { return }
        context?.delete(record)
        commit()
    }

    /// A change made here, sent on to the server. The cache already has it;
    /// a failure is only logged, and the next refresh shows the server's.
    private func onServer(_ change: @escaping (WebUIClient) async throws -> Void) {
        guard let client = server?.client else { return }
        Task {
            do {
                try await change(client)
            } catch {
                print("Error Updating Server: \(error.localizedDescription)")
            }
        }
    }

    private func commit() {
        do {
            try context?.save()
        } catch {
            print("Error Saving Chats: \(error.localizedDescription)")
        }
    }

    /// Changes one message of a session, showing it if on screen; a no-op
    /// once it's gone (retried away).
    private func update(_ id: String, in session: ChatSession, _ change: (inout ChatMessage) -> Void) {
        guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&session.messages[index])
        publish(session)
    }

    /// A failed reply's reason, worded for the transcript.
    nonisolated static func describe(_ error: Error, model: String) -> String {
        if let failure = error as? WebUIAuth.Failure {
            switch failure {
            case .noPassword: return "Sign in to the server in Settings."
            case .signIn(let message): return "The server turned down the sign-in: \(message). Check Settings."
            }
        }
        if let failure = error as? WebUIClient.Failure {
            switch failure {
            case .http(_, let message) where message.localizedCaseInsensitiveContains("not found")
                && message.localizedCaseInsensitiveContains("model"):
                return "The server has no model named \(model). Pick another below."
            case .http(let status, _) where status == 502 || status == 503 || (520...530).contains(status):
                // Cloudflare's codes for a tunnel or server that isn't there.
                return "Couldn't reach the server (\(status)). Check that it is on and Open WebUI is running."
            case .http, .notFound, .stream:
                return "The server couldn't start the reply: \(failure.localizedDescription)"
            }
        }
        if let error = error as? WebUISocket.Failure {
            return "Couldn't open the live connection: \(error.localizedDescription)"
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut:
                return "The server took too long to answer. Try again in a minute."
            case .appTransportSecurityRequiresSecureConnection:
                return "The server needs an https:// address. Change it in Settings."
            default:
                return "Couldn't reach the server. Check the address in Settings and that the server is on."
            }
        }
        return error.localizedDescription
    }
}
