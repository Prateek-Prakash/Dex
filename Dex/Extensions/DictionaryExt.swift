//
//  DictionaryExt.swift
//  Dex
//
//  Created by Prateek Prakash on 12/21/23.
//

import Foundation

extension Dictionary: @retroactive RawRepresentable where Key == String, Value == String {
    public init?(rawValue: String) {
        guard let rawData = rawValue.data(using: .utf8) else {
            return nil
        }
        guard let decodedDict = try? JSONDecoder().decode([String:String].self, from: rawData) else {
            return nil
        }
        self = decodedDict
    }
    
    public var rawValue: String {
        guard let rawData = try? JSONEncoder().encode(self) else {
            return "{}"
        }
        guard let encodedString = String(data: rawData, encoding: .utf8) else {
            return "{}"
        }
        return encodedString
    }
}
