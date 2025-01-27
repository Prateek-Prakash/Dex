//
//  ArraryExt.swift
//  Dex
//
//  Created by Prateek Prakash on 12/21/23.
//

import Foundation

extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let rawData = rawValue.data(using: .utf8),
              let decodedArray = try? JSONDecoder().decode([Element].self, from: rawData)
        else {
            return nil
        }
        self = decodedArray
    }
    
    public var rawValue: String {
        guard let rawData = try? JSONEncoder().encode(self),
              let encodedArray = String(data: rawData, encoding: .utf8)
        else {
            return "[]"
        }
        return encodedArray
    }
}
