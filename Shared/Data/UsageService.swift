//
//  UsageService.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// The single place every surface goes to fetch Claude Code usage. It owns the
/// whole flow — get a valid access token from the app's OAuth session, build the
/// `claude-code` User-Agent, call the usage endpoint — so the app and the widget
/// never duplicate it. Lives in `Shared/` and is compiled into both targets.
///
/// The token is used only to authorize the request and is never stored outside
/// the keychain, logged, or returned.
enum UsageService {

    /// The outcome of a fetch: the HTTP status, the raw (pretty-printed) body for
    /// inspection, and the mapped snapshot — `nil` when the status wasn't 200 or
    /// the body didn't decode. Only auth/transport problems throw.
    struct Fetched {
        let status: Int
        let rawBody: String
        let snapshot: UsageSnapshot?
    }

    /// Gets a valid token, calls the usage endpoint, and maps the response onto
    /// a `UsageSnapshot` stamped with the fetch time.
    static func fetch(now: Date = Date()) async throws -> Fetched {
        let token = try await OAuthSession.shared.validAccessToken()
        let result = try await UsageEndpoint.fetch(
            token: token,
            userAgent: ClaudeCodeVersion.userAgent()
        )
        let snapshot: UsageSnapshot? = result.statusCode == 200
            ? try? UsageEndpointResponse.decode(result.data).toSnapshot(asOf: now)
            : nil
        return Fetched(status: result.statusCode, rawBody: result.prettyBody, snapshot: snapshot)
    }
}
