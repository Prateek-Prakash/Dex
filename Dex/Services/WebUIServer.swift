//
//  WebUIServer.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation

/// What `ChatVM` needs of the server to run replies: requests, and the live
/// channel replies stream over. A protocol so tests can stand in for the
/// socket.
@MainActor
protocol ReplyServer: AnyObject {
    var client: WebUIClient { get }
    /// Called with every live event, and `.disconnected` when the channel drops.
    var onEvent: (WebUIEvent) -> Void { get set }
    /// The live channel's id, connecting first if it's down.
    func sessionID() async throws -> String
    /// Marks a chat read on the server.
    func markRead(chatID: String)
}

/// An Open WebUI server: its client, and one live channel shared by every chat.
@MainActor
final class WebUIServer: ReplyServer {
    let client: WebUIClient
    var onEvent: (WebUIEvent) -> Void = { _ in }
    private let socket: WebUISocket
    private var sid: String?
    /// The connection under way; callers that need it meanwhile share it.
    private var connecting: Task<String, Error>?
    private var pump: Task<Void, Never>?

    init(client: WebUIClient, socket: WebUISocket) {
        self.client = client
        self.socket = socket
    }

    func sessionID() async throws -> String {
        if let sid { return sid }
        if let connecting { return try await connecting.value }
        let task = Task { () throws -> String in
            let (sid, events) = try await socket.connect()
            self.sid = sid
            pump = Task { [weak self] in
                for await event in events {
                    if event == .disconnected { break }
                    self?.onEvent(event)
                }
                // The channel dropped (the app went to the background, the
                // network changed): the next reply connects again.
                guard let self, self.sid == sid else { return }
                self.sid = nil
                self.onEvent(.disconnected)
            }
            return sid
        }
        connecting = task
        defer { connecting = nil }
        return try await task.value
    }

    func markRead(chatID: String) {
        Task { await socket.markRead(chatID: chatID) }
    }

    /// Closes the live channel. Replies streaming over it hear that it
    /// dropped, so they go on reading the server instead.
    func disconnect() {
        pump?.cancel()
        let wasConnected = sid != nil
        sid = nil
        Task { await socket.disconnect() }
        if wasConnected { onEvent(.disconnected) }
    }
}
