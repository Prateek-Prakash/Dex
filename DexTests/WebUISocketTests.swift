//
//  WebUISocketTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import Testing
@testable import Dex

struct WebUISocketTests {
    @Test(arguments: [
        ("https://webui.teek.dev", "wss://webui.teek.dev/ws/socket.io/?EIO=4&transport=websocket"),
        ("http://192.168.1.5:3000", "ws://192.168.1.5:3000/ws/socket.io/?EIO=4&transport=websocket"),
        ("https://host/webui/", "wss://host/webui/ws/socket.io/?EIO=4&transport=websocket"),
    ])
    func socketURL(_ base: String, _ expected: String) throws {
        #expect(WebUISocket.url(for: try #require(URL(string: base)))?.absoluteString == expected)
    }

    @Test func parsesHandshakeFrames() {
        #expect(SocketPacket.parse(#"0{"sid":"engine","upgrades":[],"pingInterval":25000}"#) == .open)
        #expect(SocketPacket.parse("2") == .ping)
        #expect(SocketPacket.parse(#"40{"sid":"U2RMKlZDZEeBJbjxAAAF"}"#) == .connected(sid: "U2RMKlZDZEeBJbjxAAAF"))
        #expect(SocketPacket.parse(#"44{"message":"Not authorized"}"#) == .connectError("Not authorized"))
        #expect(SocketPacket.parse("41") == .disconnect)
        #expect(SocketPacket.parse("1") == .disconnect)
        #expect(SocketPacket.parse("") == .other)
        #expect(SocketPacket.parse("6") == .other)
    }

    @Test func parsesAcks() {
        #expect(SocketPacket.parse(#"430[{"id":"u","name":"P"}]"#) == .ack(id: 0, payload: Data(#"[{"id":"u","name":"P"}]"#.utf8)))
        #expect(SocketPacket.parse("4312[]") == .ack(id: 12, payload: Data("[]".utf8)))
    }

    @Test func parsesEvents() throws {
        guard case .event(let name, let payload) = SocketPacket.parse(#"42["events",{"chat_id":"c","data":{"type":"chat:list"}}]"#) else {
            Issue.record("not an event")
            return
        }
        #expect(name == "events")
        let body = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(body["chat_id"] as? String == "c")
        guard case .event("bare", let none) = SocketPacket.parse(#"42["bare"]"#) else {
            Issue.record("not an event")
            return
        }
        #expect(String(decoding: none, as: UTF8.self) == "null")
    }

    @Test func buildsEventFrames() throws {
        let frame = try #require(SocketPacket.event("user-join", ["auth": ["token": "t"]], ack: 0))
        #expect(frame.hasPrefix("420["))
        guard case .event("user-join", let payload) = SocketPacket.parse(frame.replacingOccurrences(of: "420[", with: "42[")) else {
            Issue.record("frame didn't round-trip")
            return
        }
        #expect(try JSONSerialization.jsonObject(with: payload) as? [String: [String: String]] == ["auth": ["token": "t"]])
        #expect(SocketPacket.event("x", 1)?.hasPrefix("42[") == true)
    }

    private func event(_ type: String, _ data: String, chat: String = "c1", message: String = "a1") -> WebUIEvent? {
        WebUIEvent.decode(Data(#"{"chat_id":"\#(chat)","message_id":"\#(message)","data":{"type":"\#(type)","data":\#(data)}}"#.utf8))
    }

    @Test func decodesStreamDeltas() {
        #expect(event("response:completion", #"{"type":"response.output_text.delta","item_id":"msg_1","output_index":1,"content_index":0,"delta":"Hi"}"#)
                == .text(chatID: "c1", messageID: "a1", delta: "Hi"))
        #expect(event("response:completion", #"{"type":"response.reasoning_text.delta","item_id":"r_1","output_index":0,"delta":" simple"}"#)
                == .reasoning(chatID: "c1", messageID: "a1", itemID: "r_1", delta: " simple"))
        #expect(event("response:completion", #"{"type":"response.function_call_arguments.delta","delta":"{"}"#) == nil)
    }

    @Test func decodesSteps() {
        let started = #"{"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","id":"call_y","call_id":"call_y","name":"search_web","arguments":"","status":"in_progress"}}"#
        #expect(event("response:completion", started) == .item(chatID: "c1", messageID: "a1",
            item: .functionCall(id: "call_y", callID: "call_y", name: "search_web", arguments: ""), isDone: false))
        let done = #"{"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"call_y","call_id":"call_y","name":"fetch_url","arguments":"{\"url\": \"https://x.dev\"}","status":"completed"}}"#
        #expect(event("response:completion", done) == .item(chatID: "c1", messageID: "a1",
            item: .functionCall(id: "call_y", callID: "call_y", name: "fetch_url", arguments: #"{"url": "https://x.dev"}"#), isDone: true))
    }

    @Test func decodesFinishAndFailure() {
        let finished = #"{"done":true,"output":[{"type":"message","id":"m","content":[{"type":"output_text","text":"Hi"}]}],"usage":{"prompt_tokens":3,"completion_tokens":4}}"#
        #expect(event("chat:completion", finished) == .finished(chatID: "c1", messageID: "a1",
            output: [.message(id: "m", text: "Hi")], usage: WebUIUsage(promptTokens: 3, completionTokens: 4)))
        // Usage-only and chunk-shaped completions arrive mid-reply; they finish nothing.
        #expect(event("chat:completion", #"{"usage":{"prompt_tokens":3}}"#) == nil)
        #expect(event("chat:completion", #"{"id":"chatcmpl-1","choices":[{"finish_reason":"tool_calls","delta":{}}]}"#) == nil)
        #expect(event("chat:completion", #"{"error":{"content":"Model not found"},"done":true}"#)
                == .failed(chatID: "c1", messageID: "a1", message: "Model not found"))
    }

    @Test func decodesChatState() {
        #expect(event("chat:title", #""Open WebUI Release""#) == .title(chatID: "c1", title: "Open WebUI Release"))
        #expect(event("chat:tags", #"["General"]"#) == .tags(chatID: "c1", tags: ["General"]))
        #expect(event("chat:active", #"{"active":false,"folder_id":null}"#) == .active(chatID: "c1", isActive: false))
        #expect(event("chat:list", #"{"chat_id":"c1","folder_id":null}"#) == .listChanged(chatID: "c1"))
        #expect(event("chat:list", #"{"chat_id":"c1","last_read_at":1791569211}"#)
                == .read(chatID: "c1", at: Date(timeIntervalSince1970: 1_791_569_211)))
        #expect(event("chat:tasks:cancel", "null") == .cancelled(chatID: "c1", messageID: "a1"))
        #expect(event("chat:message:error", #"{"error":{"content":"Model not found"},"done":true}"#)
                == .failed(chatID: "c1", messageID: "a1", message: "Model not found"))
        #expect(event("source", #"{"source":{"name":"x"}}"#) == nil)
        #expect(WebUIEvent.decode(Data("not json".utf8)) == nil)
    }
}
