//
//  AnthropicOAuth.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/04/26.
//  © 2026 Rodrigo Busata.
//

import CryptoKit
import Foundation
import Security

/// The OAuth 2.0 + PKCE sign-in flow against Anthropic's consumer auth — the same
/// flow (and public client ID) Claude Code uses. Anthropic has no official
/// third-party OAuth registration, so like the usage endpoint this is
/// **unofficial**: treat it as best-effort and degrade gracefully.
///
/// The flow: open `PendingSignIn.url` in the browser → the user approves and the
/// page shows a `code#state` blob to copy → `exchange` swaps it (plus the PKCE
/// verifier) for an access + refresh token → `refresh` renews them on expiry.
enum AnthropicOAuth {

    /// Claude Code's public OAuth client ID. PKCE flows use public clients —
    /// there is no client secret.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizeBase = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    /// The "display the code" redirect — the callback page shows `code#state` for
    /// the user to copy, so the app doesn't need to run a local callback server.
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    /// The scope set this flow is known to accept (what Claude Code requests).
    /// The app only ever exercises `user:profile` — the usage endpoint.
    private static let scope = "org:create_api_key user:profile user:inference"

    /// A sign-in attempt in flight: the URL to open in the browser plus the PKCE
    /// verifier and state that must survive until the code comes back. Held in
    /// memory only.
    struct PendingSignIn {
        let url: URL
        let verifier: String
        let state: String
    }

    /// The tokens a sign-in (or refresh) produced. Persisted only via
    /// `OAuthCredentialStore` (the keychain) — never logged or written to files.
    struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date

        /// True when the access token is expired or within five minutes of it —
        /// close enough that the next request should refresh first.
        func needsRefresh(now: Date = Date()) -> Bool {
            now >= expiresAt.addingTimeInterval(-300)
        }
    }

    enum SignInError: LocalizedError {
        case emptyCode
        case transport(String)
        case server(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .emptyCode:
                return "Paste the code shown in the browser first."
            case .transport(let message):
                return message
            case .server(let status, let body):
                return "Token request failed (HTTP \(status)): \(body)"
            case .malformedResponse:
                return "The token response couldn't be parsed."
            }
        }
    }

    /// Starts a sign-in: generates a fresh PKCE verifier + state and builds the
    /// browser URL that asks the user to approve access.
    static func beginSignIn() -> PendingSignIn {
        let verifier = randomURLSafeToken()
        let state = randomURLSafeToken()
        var components = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return PendingSignIn(url: components.url!, verifier: verifier, state: state)
    }

    /// Exchanges the pasted `code#state` blob for tokens. The blob comes straight
    /// from the user's clipboard, so it's trimmed and split defensively.
    static func exchange(pastedCode: String, pending: PendingSignIn) async throws -> Credentials {
        let trimmed = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SignInError.emptyCode }
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let payload: [String: Any] = [
            "grant_type": "authorization_code",
            "code": parts[0],
            "state": parts.count > 1 ? parts[1] : pending.state,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": pending.verifier,
        ]
        return try await requestTokens(payload, fallbackRefreshToken: nil)
    }

    /// Renews an expired access token. Anthropic may rotate the refresh token;
    /// when the response omits one, the current token is kept.
    static func refresh(refreshToken: String) async throws -> Credentials {
        let payload: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        return try await requestTokens(payload, fallbackRefreshToken: refreshToken)
    }

    // MARK: - Token endpoint

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double
    }

    private static func requestTokens(
        _ payload: [String: Any],
        fallbackRefreshToken: String?
    ) async throws -> Credentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SignInError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SignInError.transport("Unexpected (non-HTTP) response.")
        }
        guard http.statusCode == 200 else {
            // Error bodies are short JSON like {"error":"invalid_grant"} — no
            // secrets — so a snippet is safe (and useful) to surface.
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw SignInError.server(http.statusCode, body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tokens = try? decoder.decode(TokenResponse.self, from: data) else {
            throw SignInError.malformedResponse
        }
        guard let refreshToken = tokens.refreshToken ?? fallbackRefreshToken else {
            throw SignInError.malformedResponse
        }
        return Credentials(
            accessToken: tokens.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(tokens.expiresIn)
        )
    }

    // MARK: - PKCE

    /// 32 cryptographically-random bytes, base64url-encoded — used for both the
    /// PKCE verifier and the state parameter.
    private static func randomURLSafeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    /// S256 code challenge: base64url(SHA-256(verifier)).
    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
