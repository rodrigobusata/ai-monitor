//
//  UsageEndpoint.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Calls the **unofficial** OAuth usage endpoint that Claude Code's `/usage`
/// command uses. Undocumented and may break without notice — every caller must
/// degrade gracefully.
enum UsageEndpoint {

    private static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// What a fetch produced: the HTTP status, the raw body (for decoding), and a
    /// pretty-printed copy (for error messages). No token is ever included here.
    struct RawResult {
        let statusCode: Int
        let data: Data
        let prettyBody: String
    }

    enum FetchError: LocalizedError {
        case notHTTP
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notHTTP: return "Unexpected (non-HTTP) response."
            case .transport(let message): return message
            }
        }
    }

    /// Performs one authenticated GET. The `token` is used only to build the
    /// Authorization header for this request and is never stored or logged.
    static func fetch(token: String, userAgent: String) async throws -> RawResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // The endpoint rate-limits (429s) requests without a claude-code User-Agent.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }

        return RawResult(
            statusCode: http.statusCode,
            data: data,
            prettyBody: prettyPrint(data)
        )
    }

    /// Re-serializes JSON with sorted keys + indentation for readable display;
    /// falls back to the UTF-8 text (or a byte count) when the body isn't JSON.
    private static func prettyPrint(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
               withJSONObject: object,
               options: [.prettyPrinted, .sortedKeys]
           ),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "(\(data.count) bytes, not text)"
    }
}
