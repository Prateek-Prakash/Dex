//
//  KeychainServiceTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Testing
@testable import Dex

@Suite(.serialized)
struct KeychainServiceTests {
    let account = "tests.keychain"

    @Test func savesLoadsAndReplaces() {
        defer { KeychainService.save("", for: account) }
        KeychainService.save("first", for: account)
        #expect(KeychainService.load(account) == "first")
        KeychainService.save("second", for: account)
        #expect(KeychainService.load(account) == "second")
    }

    @Test func emptyValueRemovesItem() {
        KeychainService.save("value", for: account)
        KeychainService.save("", for: account)
        #expect(KeychainService.load(account) == "")
    }
}
