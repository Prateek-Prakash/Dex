//
//  OllamaTypes.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation

/// An installed model, as Ollama describes it (through Open WebUI).
struct OllamaModel: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let size: Int
    let digest: String
    let details: Details
    let capabilities: [String]?

    var id: String { name }

    /// "gemma4:12b" -> "gemma4"; "library/model" names keep their namespace.
    var baseName: String { String(name.split(separator: ":", maxSplits: 1).first ?? Substring(name)) }

    /// "gemma4:12b" -> "12b"; a name without a tag is "latest".
    var tag: String {
        let parts = name.split(separator: ":", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : "latest"
    }

    struct Details: Codable, Sendable, Hashable {
        let format: String?
        let family: String?
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case format, family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

/// One line of a `/api/pull` stream.
struct OllamaPullProgress: Decodable, Sendable {
    let status: String?
    let total: Int?
    let completed: Int?
    let error: String?
}

/// Any JSON value.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }
}
