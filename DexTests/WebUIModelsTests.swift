//
//  WebUIModelsTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import Testing
@testable import Dex

/// Shapes taken from a real Open WebUI 0.11.4 server, trimmed.
enum WebUIFixtures {
    /// A web-search reply that was retried: `a1` and `a2` both answer `u1`,
    /// and `a2` is on show.
    static let chat = """
    {"id":"c1","user_id":"u","title":"Paris Weather","pinned":true,"folder_id":"f1","archived":false,
     "updated_at":1791569211,"created_at":1791569198,"meta":{"tags":["general"]},"share_id":null,
     "chat":{"id":"","title":"Paris Weather","models":["gemma4:12b"],"tags":["general"],"timestamp":1,
       "messages":[{"role":"user","content":"Weather in Paris?"}],
       "history":{"currentId":"a2","messages":{
         "u1":{"id":"u1","parentId":null,"childrenIds":["a1","a2"],"role":"user","content":"Weather in Paris?",
               "timestamp":1791569198,"models":["gemma4:12b"]},
         "a1":{"id":"a1","parentId":"u1","childrenIds":[],"role":"assistant","content":"First try.","done":true,
               "model":"gemma4:12b","timestamp":1791569199},
         "a2":{"id":"a2","parentId":"u1","childrenIds":[],"role":"assistant","content":"Clear, 17°C.","done":true,
               "model":"gemma4:12b","timestamp":1791569200,
               "usage":{"input_tokens":9622,"output_tokens":135,"prompt_tokens":4981,"completion_tokens":78,"response_token/s":93.98},
               "output":[
                 {"type":"reasoning","id":"r1","status":"completed","start_tag":"<think>","end_tag":"</think>",
                  "attributes":{"type":"reasoning_content"},"content":[{"type":"output_text","text":"Look it "},{"type":"output_text","text":"up."}],
                  "summary":[],"started_at":1,"duration":2},
                 {"type":"function_call","id":"call_1","call_id":"call_1","name":"search_web",
                  "arguments":"{\\"query\\": \\"current weather in Paris\\"}","status":"completed"},
                 {"type":"function_call_output","id":"fco_1","call_id":"call_1","status":"completed",
                  "output":[{"type":"input_text","text":"[results]"}]},
                 {"type":"message","id":"msg_1","status":"completed","role":"assistant",
                  "content":[{"type":"output_text","text":"Clear, 17°C."}]},
                 {"type":"web_search_call","id":"ws_1"}
               ]}
       }}},
     "variables":{},"tasks":null,"summary":null,"current_message_id":"a2","context_usage":null}
    """

    static let models = """
    {"data":[
      {"id":"qwen3.5:9b","name":"qwen3.5:9b","object":"model","created":0,"owned_by":"ollama",
       "ollama":{"name":"qwen3.5:9b","size":6600000000,"digest":"56671c2ab9384d0e","modified_at":"2026-10-06T03:25:43.9701648-04:00","details":{"format":"gguf","family":"qwen3","parameter_size":"9B",
                 "quantization_level":"Q4_K_M","context_length":131072},"capabilities":["tools","thinking","completion"],
                 "connection_type":"local","urls":[0]},
       "loaded":true,"connection_type":"local","tags":[],"actions":[],"filters":[]},
      {"id":"arena-model","name":"Arena Model","info":{"meta":{"description":"Vote.","model_ids":null}},
       "object":"model","created":0,"owned_by":"arena","arena":true,"actions":[],"filters":[],"tags":[]},
      {"id":"gemma4:12b","name":"Gemma","info":{"meta":{"hidden":true}},"ollama":{"size":8100000000}},
      {"id":"dolphin3:8b","name":"dolphin3:8b","info":{"meta":{"hidden":false}}}
    ]}
    """
}

struct WebUIModelsTests {
    @Test func chatDecodesTreeAndOutput() throws {
        let chat = try JSONDecoder().decode(WebUIChat.self, from: Data(WebUIFixtures.chat.utf8))
        #expect(chat.pinned == true)
        #expect(chat.folderId == "f1")
        #expect(chat.chat.tags == ["general"])
        let reply = try #require(chat.chat.history.messages["a2"])
        #expect(reply.done == true)
        #expect(reply.usage == WebUIUsage(promptTokens: 4981, completionTokens: 78))
        #expect(reply.output == [
            .reasoning(id: "r1", text: "Look it up.", duration: 2),
            .functionCall(id: "call_1", callID: "call_1", name: "search_web", arguments: #"{"query": "current weather in Paris"}"#),
            .functionCallOutput(callID: "call_1", text: "[results]"),
            .message(id: "msg_1", text: "Clear, 17°C."),
            .other(type: "web_search_call"),
        ])
        let question = try #require(chat.chat.history.messages["u1"])
        #expect(question.done == nil)
        #expect(question.output == nil)
    }

    @Test func currentBranchFollowsCurrentIdToRoot() throws {
        let chat = try JSONDecoder().decode(WebUIChat.self, from: Data(WebUIFixtures.chat.utf8))
        #expect(chat.chat.history.currentBranch.map(\.id) == ["u1", "a2"])
    }

    @Test func currentBranchSurvivesLoopsAndGaps() throws {
        let looped = """
        {"currentId":"b","messages":{
          "a":{"id":"a","parentId":"b","role":"user","content":"x"},
          "b":{"id":"b","parentId":"a","role":"assistant","content":"y"}}}
        """
        #expect(try JSONDecoder().decode(WebUIHistory.self, from: Data(looped.utf8)).currentBranch.map(\.id) == ["a", "b"])
        let empty = #"{"currentId":null,"messages":{}}"#
        #expect(try JSONDecoder().decode(WebUIHistory.self, from: Data(empty.utf8)).currentBranch.isEmpty)
        let missing = #"{"currentId":"gone","messages":{}}"#
        #expect(try JSONDecoder().decode(WebUIHistory.self, from: Data(missing.utf8)).currentBranch.isEmpty)
    }

    @Test func modelsListOnlyVisibleOnes() throws {
        struct Response: Decodable { let data: [WebUIModel] }
        let models = try JSONDecoder().decode(Response.self, from: Data(WebUIFixtures.models.utf8)).data
        #expect(models.filter(\.isListed).map(\.id) == ["qwen3.5:9b", "dolphin3:8b"])
        let qwen = models[0]
        #expect(qwen.details?.parameterSize == "9B")
        #expect(qwen.details?.contextLength == 131_072)
        #expect(qwen.shortDigest == "56671c2ab938")
        #expect(qwen.capabilities == ["tools", "thinking", "completion"])
        #expect(qwen.isLoaded)
        #expect(qwen.modifiedAt == WebUIModel.date("2026-10-06T03:25:43-04:00"))
        #expect(qwen.baseName == "qwen3.5")
        #expect(qwen.tag == "9b")
        #expect(models[1].isArena)
        #expect(models[2].isHidden)
        #expect(models[3].size == nil)
        #expect(models[3].capabilities.isEmpty)
    }

    @Test func ollamaTimesKeepTheirOffset() {
        let date = WebUIModel.date("2026-10-07T19:39:04.6354653-04:00")
        #expect(date == WebUIModel.date("2026-10-07T23:39:04Z"))
        #expect(WebUIModel.date("not a date") == nil)
    }

    @Test func modelInfoNamesBaseModelMakerAndLicense() throws {
        let json = #"{"license":"…","model_info":{"general.base_model.0.name":"Gemma 4 12B","general.base_model.0.organization":"Google","general.license":"apache-2.0","general.parameter_count":11907350576}}"#
        #expect(try JSONDecoder().decode(WebUIModelInfo.self, from: Data(json.utf8))
                == WebUIModelInfo(baseModel: "Gemma 4 12B", maker: "Google", license: "apache-2.0"))
        let bare = try JSONDecoder().decode(WebUIModelInfo.self, from: Data(#"{"model_info":{}}"#.utf8))
        #expect(bare == WebUIModelInfo(baseModel: nil, maker: nil, license: nil))
    }

    @Test func detailsLabels() {
        #expect(ModelDetailsView.contextLabel(262_144) == "256K")
        #expect(ModelDetailsView.contextLabel(65_536) == "64K")
        #expect(ModelDetailsView.contextLabel(4_000) == 4_000.formatted())
        #expect(ModelDetailsView.capabilitiesLabel(["completion", "vision", "tools", "thinking"]) == "Thinking • Tools • Vision")
        #expect(ModelDetailsView.capabilitiesLabel(["completion"]) == nil)
    }

    @Test(arguments: [
        (#"{"id":"c","title":"t","updated_at":20,"created_at":1,"last_read_at":10}"#, true),
        (#"{"id":"c","title":"t","updated_at":20,"created_at":1,"last_read_at":20}"#, false),
        (#"{"id":"c","title":"t","updated_at":20,"created_at":1,"last_read_at":null}"#, true),
        (#"{"id":"c","title":"t","updated_at":20,"created_at":1,"last_read_at":10,"active":true}"#, false),
    ])
    func unreadMatchesServerRule(_ json: String, _ unread: Bool) throws {
        #expect(try JSONDecoder().decode(WebUIChatSummary.self, from: Data(json.utf8)).isUnread == unread)
    }

    @Test func newChatRequestSendsNullParent() throws {
        let request = WebUIReplyRequest(
            model: "gemma4:12b", sessionID: "sid", id: "a1", chatID: nil, parentID: nil,
            userMessage: .init(id: "u1", parentId: nil, childrenIds: ["a1"], content: "Hi", timestamp: 5, models: ["gemma4:12b"]),
            messages: [["role": "user", "content": "Hi"]], backgroundTasks: .init())
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json.keys.contains("parent_id"))
        #expect(json["parent_id"] is NSNull)
        #expect(json["chat_id"] == nil)
        #expect(json["session_id"] as? String == "sid")
        #expect(json["stream"] as? Bool == true)
        #expect((json["features"] as? [String: Bool]) == ["web_search": true])
        #expect((json["background_tasks"] as? [String: Bool]) == ["title_generation": true, "tags_generation": true])
        let user = try #require(json["user_message"] as? [String: Any])
        #expect(user["role"] as? String == "user")
        #expect(user["parentId"] is NSNull)
        #expect(user["childrenIds"] as? [String] == ["a1"])
    }

    @Test func followUpLeavesHistoryToServer() throws {
        let request = WebUIReplyRequest(
            model: "m", sessionID: "sid", id: "a2", chatID: "c1", parentID: "a1",
            userMessage: .init(id: "u2", parentId: "a1", childrenIds: ["a2"], content: "More", timestamp: 6, models: ["m"]))
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["chat_id"] as? String == "c1")
        #expect(json["parent_id"] as? String == "a1")
        #expect(json["messages"] == nil)
        #expect(json["background_tasks"] == nil)
    }

    @Test func temporaryChatIDIsLocal() {
        #expect(WebUIReplyRequest.temporaryChatID(sessionID: "abc") == "local:abc")
    }
}
