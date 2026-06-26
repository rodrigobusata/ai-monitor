//
//  ClaudeCodeVersion.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Builds the `claude-code/<version>` User-Agent the usage endpoint expects.
/// The version is best-effort: we ask the installed `claude` CLI, and fall back
/// to a recent default if it can't be found (the endpoint mainly cares that the
/// agent string is claude-code-shaped).
enum ClaudeCodeVersion {

    private static let fallback = "1.0.0"

    /// The full `User-Agent` header value, e.g. `claude-code/1.2.3`.
    static func userAgent() -> String {
        "claude-code/\(detect() ?? fallback)"
    }

    /// Runs `claude --version` via a login shell (to pick up the user's PATH) and
    /// extracts the first semantic version it prints. Returns nil on any failure.
    private static func detect() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "claude --version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return semanticVersion(in: output)
    }

    /// First `X.Y.Z` substring in the given text.
    private static func semanticVersion(in text: String) -> String? {
        guard let range = text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }
}
