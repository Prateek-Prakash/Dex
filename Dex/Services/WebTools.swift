//
//  WebTools.swift
//  Dex
//
//  Created by Prateek Prakash on 10/8/26.
//

import Foundation

/// One search or page read a reply made, as kept with it: what was asked
/// and the sources found. The raw text the model read is never kept, so a
/// later turn doesn't carry it.
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
}

/// The web search and fetch tools a model may call, run through
/// ollama.com. One reply gets a few of each; past that, the model is told
/// to answer with what it has.
enum WebTools {
    static let maxRounds = 5
    static let maxSearches = 5
    static let maxFetches = 3
    /// What the model reads of each search hit and each page, in characters.
    static let snippetLength = 1_000
    static let pageLength = 6_000

    static let definitions: [OllamaTool] = [
        OllamaTool(function: .init(
            name: "web_search",
            description: "Search the web for current information. Returns titles, URLs and snippets.",
            parameters: .init(properties: ["query": .init(type: "string", description: "What to search for")],
                              required: ["query"]))),
        OllamaTool(function: .init(
            name: "web_fetch",
            description: "Read a web page's text, by its URL.",
            parameters: .init(properties: ["url": .init(type: "string", description: "The page's full URL")],
                              required: ["url"])))
    ]

    /// How many calls one reply has left.
    struct Budget: Sendable {
        var searches = WebTools.maxSearches
        var fetches = WebTools.maxFetches
    }

    /// The lookup a call will make, before it runs; nil for a tool Dex
    /// doesn't have.
    static func lookup(for call: OllamaToolCall) -> WebLookup? {
        switch call.function.name {
        case "web_search":
            WebLookup(kind: .search, subject: call.function.arguments["query"]?.string ?? "")
        case "web_fetch":
            WebLookup(kind: .fetch, subject: call.function.arguments["url"]?.string ?? "")
        default:
            nil
        }
    }

    /// Runs one call: the text the model reads back, and the lookup as kept.
    /// Every failure is answered in words, so the model can carry on.
    static func run(_ call: OllamaToolCall, client: OllamaClient, budget: inout Budget) async -> (result: String, lookup: WebLookup?) {
        guard var lookup = lookup(for: call) else {
            return ("There is no tool named \(call.function.name).", nil)
        }
        guard !lookup.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lookup.state = .failed
            lookup.error = lookup.kind == .search ? "The query was empty." : "The URL was empty."
            return (lookup.error ?? "", lookup)
        }
        switch lookup.kind {
        case .search:
            guard budget.searches > 0 else {
                lookup.state = .failed
                lookup.error = "No searches left for this answer."
                return ("No searches left for this answer. Answer with what you have.", lookup)
            }
            budget.searches -= 1
            do {
                let results = try await client.webSearch(lookup.subject)
                lookup.state = .done
                lookup.sources = results.map { .init(title: title($0.title, url: $0.url), url: $0.url) }
                return (searchText(results), lookup)
            } catch {
                // Stopped: not a failure; the reply ends as stopped.
                if isCancellation(error) { return ("Stopped.", lookup) }
                lookup.state = .failed
                lookup.error = "The search failed (\(reason(error)))."
                print("Error Web Search: \(error.localizedDescription)")
                return (lookup.error ?? "", lookup)
            }
        case .fetch:
            guard budget.fetches > 0 else {
                lookup.state = .failed
                lookup.error = "No page reads left for this answer."
                return ("No page reads left for this answer. Answer with what you have.", lookup)
            }
            budget.fetches -= 1
            do {
                let page = try await client.webFetch(lookup.subject)
                lookup.state = .done
                lookup.sources = [.init(title: title(page.title, url: lookup.subject), url: lookup.subject)]
                return (pageText(page), lookup)
            } catch {
                if isCancellation(error) { return ("Stopped.", lookup) }
                lookup.state = .failed
                lookup.error = "The page couldn't be read (\(reason(error)))."
                print("Error Web Fetch: \(error.localizedDescription)")
                return (lookup.error ?? "", lookup)
            }
        }
    }

    static func searchText(_ results: [OllamaWebResult]) -> String {
        guard !results.isEmpty else { return "No results." }
        return results.map { result in
            [result.title, result.url, result.content.map { trim($0, to: snippetLength) }]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    static func pageText(_ page: OllamaWebPage) -> String {
        let content = trim(page.content ?? "", to: pageLength)
        guard !content.isEmpty else { return "The page has no text." }
        return [page.title, content].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// `text` cut to `length` characters, marked when cut.
    static func trim(_ text: String, to length: Int) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > length else { return text }
        return String(text.prefix(length)) + " […]"
    }

    /// An error's description without its closing period, to sit in parentheses.
    static func reason(_ error: Error) -> String {
        var text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func title(_ title: String?, url: String) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? (URL(string: url)?.host() ?? url) : title
    }
}
