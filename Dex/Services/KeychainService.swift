//
//  KeychainService.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation
import Security

/// Strings kept in the Keychain, one per account name.
enum KeychainService {
    private static let service = "Teekzilla.Dex"

    static let accessClientID = "ollama.access.id"
    static let accessClientSecret = "ollama.access.secret"
    static let ollamaAPIKey = "ollama.com.key"
    /// The Open WebUI account's password, sent only to sign in.
    static let webUIPassword = "webui.password"
    /// The login token, its expiry and whose it is, as JSON.
    static let webUIToken = "webui.token"

    static func load(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves `value`, or removes the item when it's empty.
    static func save(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
