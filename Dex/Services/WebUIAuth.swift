//
//  WebUIAuth.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation

/// Signs in to Open WebUI and keeps the login token. The token is cached in
/// the Keychain across launches and replaced shortly before it expires, or
/// when the server turns it down; the password is only sent to sign in.
actor WebUIAuth {
    /// The login token and whose it is: a cached token is only reused for the
    /// same server and email.
    struct Token: Codable, Equatable, Sendable {
        let value: String
        /// Seconds since 1970; nil never expires.
        let expiresAt: Int?
        let owner: String
        /// When it was issued, seconds since 1970: how long it lasts sets
        /// how early it is replaced.
        var issuedAt: Int?
    }

    enum Failure: LocalizedError, Equatable {
        case noPassword
        case signIn(String)

        var errorDescription: String? {
            switch self {
            case .noPassword: "Sign in failed: no password"
            case .signIn(let message): message.isEmpty ? "Sign in failed" : "Sign in failed: \(message)"
            }
        }
    }

    /// A token this close to expiring is replaced before use; a short-lived
    /// one at a quarter of its lifetime instead, so it is used at all.
    static let renewalMargin: TimeInterval = 24 * 60 * 60

    let baseURL: URL
    let email: String
    private let passwordAccount: String
    private let tokenAccount: String
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var token: Token?
    /// The sign-in under way; callers that need a token meanwhile share it.
    private var signInTask: Task<Token, Error>?

    init(baseURL: URL, email: String,
         passwordAccount: String = KeychainService.webUIPassword,
         tokenAccount: String = KeychainService.webUIToken,
         session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.email = email
        self.passwordAccount = passwordAccount
        self.tokenAccount = tokenAccount
        self.session = session
        self.now = now
        let owner = Self.owner(baseURL: baseURL, email: email)
        let cached = try? JSONDecoder().decode(Token.self, from: Data(KeychainService.load(tokenAccount).utf8))
        token = cached?.owner == owner ? cached : nil
    }

    private var owner: String { Self.owner(baseURL: baseURL, email: email) }

    private static func owner(baseURL: URL, email: String) -> String {
        baseURL.absoluteString + "|" + email.lowercased()
    }

    /// A token good for at least `renewalMargin`, signing in when needed.
    func validToken() async throws -> String {
        if let token, isFresh(token) { return token.value }
        return try await signIn().value
    }

    /// After the server turned `rejected` down: a new token, unless another
    /// caller already replaced it.
    func renew(rejected: String) async throws -> String {
        if let token, token.value != rejected, isFresh(token) { return token.value }
        return try await signIn().value
    }

    /// Forgets the cached token, e.g. when the account changes.
    func signOut() {
        signInTask?.cancel()
        signInTask = nil
        token = nil
        KeychainService.save("", for: tokenAccount)
    }

    private func isFresh(_ token: Token) -> Bool {
        guard let expiresAt = token.expiresAt else { return true }
        var margin = Self.renewalMargin
        if let issuedAt = token.issuedAt, expiresAt > issuedAt {
            margin = min(margin, TimeInterval(expiresAt - issuedAt) / 4)
        }
        return TimeInterval(expiresAt) - now().timeIntervalSince1970 > margin
    }

    private func signIn() async throws -> Token {
        if let signInTask { return try await signInTask.value }
        let password = KeychainService.load(passwordAccount)
        let (baseURL, email, owner, session, issuedAt) = (baseURL, email, owner, session, Int(now().timeIntervalSince1970))
        let task = Task { () throws -> Token in
            guard !password.isEmpty else { throw Failure.noPassword }
            var token = try await Self.signIn(baseURL: baseURL, email: email, password: password,
                                              owner: owner, session: session)
            token.issuedAt = issuedAt
            return token
        }
        signInTask = task
        // A sign-out while waiting replaces or drops `signInTask`; this
        // sign-in then neither clears a newer one nor stores its token.
        defer { if signInTask == task { signInTask = nil } }
        let token = try await task.value
        guard signInTask == task else { throw CancellationError() }
        self.token = token
        if let data = try? JSONEncoder().encode(token) {
            KeychainService.save(String(decoding: data, as: UTF8.self), for: tokenAccount)
        }
        return token
    }

    private static func signIn(baseURL: URL, email: String, password: String, owner: String,
                               session: URLSession) async throws -> Token {
        struct Body: Encodable { let email: String; let password: String }
        struct Response: Decodable {
            let token: String
            let expiresAt: Int?
            enum CodingKeys: String, CodingKey {
                case token
                case expiresAt = "expires_at"
            }
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/auths/signin"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(email: email, password: password))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let body = try? JSONDecoder().decode(Response.self, from: data) else {
            throw Failure.signIn(WebUIClient.detail(data) ?? (status == 200 ? "" : "HTTP \(status)"))
        }
        return Token(value: body.token, expiresAt: body.expiresAt, owner: owner)
    }
}
