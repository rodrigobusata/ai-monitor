//
//  OAuthSession.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/04/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Hands out a valid access token for authenticated requests, refreshing (and
/// re-persisting) expired tokens behind a single actor so concurrent fetches
/// can't race a refresh-token rotation.
actor OAuthSession {

    static let shared = OAuthSession()

    enum SessionError: LocalizedError {
        case notSignedIn

        var errorDescription: String? {
            "Not signed in. Use “Sign in with Claude” below."
        }
    }

    /// The current access token, refreshed first if it's expired (or about to
    /// be). Throws `notSignedIn` when there are no stored credentials.
    func validAccessToken() async throws -> String {
        guard let stored = OAuthCredentialStore.load() else {
            throw SessionError.notSignedIn
        }
        guard stored.needsRefresh() else { return stored.accessToken }
        let renewed = try await AnthropicOAuth.refresh(refreshToken: stored.refreshToken)
        OAuthCredentialStore.save(renewed)
        return renewed.accessToken
    }
}
