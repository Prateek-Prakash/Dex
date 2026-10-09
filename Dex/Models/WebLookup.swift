//
//  WebLookup.swift
//  Dex
//
//  Created by Prateek Prakash on 10/8/26.
//

import Foundation

/// One search or page read a reply made, as kept with it: what was asked
/// and the sources found. The text the model read stays on the server.
struct WebLookup: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case search, fetch
    }

    enum State: String, Codable, Sendable {
        case running, done, failed
    }

    struct Source: Codable, Equatable, Sendable {
        var title: String
        var url: String
    }

    var kind: Kind
    /// The query, or the page's address.
    var subject: String
    var state: State = .running
    var sources: [Source] = []
    /// Why it failed, as shown under it.
    var error: String?

    /// Its row in the reply: what it is doing, or did.
    var label: String {
        switch (kind, state) {
        case (.search, .running): "Searching “\(subject)”…"
        case (.search, _): "Searched “\(subject)”"
        case (.fetch, .running): "Reading “\(subject)”…"
        case (.fetch, _): "Read “\(subject)”"
        }
    }

    /// The server's web tools: Open WebUI's `search_web` and `fetch_url`.
    /// Nil for any other tool, or arguments without their subject.
    init?(name: String, arguments: String) {
        let arguments = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
        switch name {
        case "search_web":
            guard let query = arguments?["query"] as? String else { return nil }
            self.init(kind: .search, subject: query)
        case "fetch_url":
            guard let url = arguments?["url"] as? String else { return nil }
            self.init(kind: .fetch, subject: url)
        default:
            return nil
        }
    }

    init(kind: Kind, subject: String, state: State = .running, sources: [Source] = [], error: String? = nil) {
        self.kind = kind
        self.subject = subject
        self.state = state
        self.sources = sources
        self.error = error
    }

    /// Done, with the sources the tool's output names: a search's hits, or
    /// the page read.
    mutating func finish(output: String) {
        state = .done
        switch kind {
        case .search:
            struct Hit: Decodable {
                let title: String?
                let link: String?
            }
            let hits = (try? JSONDecoder().decode([Hit].self, from: Data(output.utf8))) ?? []
            sources = hits.compactMap { hit in hit.link.map { .init(title: Self.title(hit.title, url: $0), url: $0) } }
        case .fetch:
            sources = [.init(title: Self.title(nil, url: subject), url: subject)]
        }
    }

    private static func title(_ title: String?, url: String) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? (URL(string: url)?.host() ?? url) : title
    }
}

/// A server reply as Dex shows it, built from the steps the server sends:
/// live, one event at a time, or whole from what it saved.
struct ReplyParts: Equatable, Sendable {
    var content = ""
    /// Each thought, in order, by the server's item id.
    private var thoughts: [(id: String, text: String)] = []
    private(set) var lookups: [WebLookup] = []
    /// Which lookup each tool call made.
    private var callIndex: [String: Int] = [:]

    init() {}

    /// The whole reply, as finished or saved. Text from separate rounds
    /// (before and after a lookup) is kept apart by a blank line.
    init(output: [WebUIOutputItem], fallback: String = "") {
        var texts: [String] = []
        for item in output {
            switch item {
            case .message(_, let text):
                texts.append(text)
            default:
                apply(item, isDone: true)
            }
        }
        let joined = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        content = joined.isEmpty ? fallback : joined
    }

    var thinking: String? {
        let text = thoughts.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    static func == (lhs: ReplyParts, rhs: ReplyParts) -> Bool {
        lhs.content == rhs.content && lhs.thinking == rhs.thinking && lhs.lookups == rhs.lookups
    }

    mutating func appendText(_ delta: String) {
        // The stream can open with a newline the saved reply doesn't have.
        content += content.isEmpty ? String(delta.drop { $0.isNewline }) : delta
    }

    mutating func appendThought(_ delta: String, itemID: String) {
        if let index = thoughts.firstIndex(where: { $0.id == itemID }) {
            thoughts[index].text += delta
        } else {
            thoughts.append((itemID, delta))
        }
    }

    /// A step that began or finished.
    mutating func apply(_ item: WebUIOutputItem, isDone: Bool) {
        switch item {
        case .reasoning(let id, let text, _):
            // A finished thought replaces what streamed of it.
            guard isDone, !text.isEmpty else { return }
            if let index = thoughts.firstIndex(where: { $0.id == id }) {
                thoughts[index].text = text
            } else {
                thoughts.append((id, text))
            }
        case .functionCall(_, let callID, let name, let arguments):
            // Started with empty arguments; the subject comes once it's done.
            guard let lookup = WebLookup(name: name, arguments: arguments) else { return }
            if let index = callIndex[callID] {
                lookups[index].subject = lookup.subject
            } else {
                callIndex[callID] = lookups.count
                lookups.append(lookup)
            }
        case .functionCallOutput(let callID, let text):
            guard let index = callIndex[callID] else { return }
            lookups[index].finish(output: text)
        case .message, .other:
            break
        }
    }
}
