//
//  ClaudeCodeLogParser.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Sums local Claude Code token usage from the transcript logs under
/// `~/.claude/projects/**/*.jsonl`, grouped by model and scoped to a time window.
/// Every assistant turn is one JSON line with a `message.usage` block; resumed
/// sessions replay turns, so lines are deduplicated by `requestId`.
///
/// A full scan reads tens of thousands of lines and takes a few seconds, so it
/// must run off the main thread. `signature()` is a cheap stat-only fingerprint
/// the caller checks first, re-parsing only when the logs actually changed.
/// Everything here stays on device; no network, no token, nothing written out.
enum ClaudeCodeLogParser {

    /// A cheap fingerprint of the log directory — file count, total byte size,
    /// and the newest modification time. Unchanged fingerprint ⇒ no need to
    /// re-parse, which keeps the routine refresh cycle off the multi-second scan.
    struct Signature: Equatable {
        let fileCount: Int
        let totalSize: Int
        let latestModified: TimeInterval
    }

    private static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    private static func logFiles() -> [URL] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files
    }

    /// A stat-only fingerprint of the logs. Fast (no file contents are read).
    static func signature() -> Signature {
        var count = 0
        var totalSize = 0
        var latest: TimeInterval = 0
        for url in logFiles() {
            count += 1
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            totalSize += values?.fileSize ?? 0
            if let modified = values?.contentModificationDate?.timeIntervalSince1970, modified > latest {
                latest = modified
            }
        }
        return Signature(fileCount: count, totalSize: totalSize, latestModified: latest)
    }

    /// The start of the trailing 30-day window in the user's local time zone — the
    /// default span for the cost estimate, so it always reflects roughly the last
    /// month of usage rather than resetting on a calendar boundary. Anchored to the
    /// start of the day so the value only advances once per day (keeping the parse
    /// cache stable within a day) while the window still slides forward over time.
    static func startOfTrailing30Days(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
    }

    /// Streams every log file and sums token usage per model across deduplicated
    /// assistant turns whose timestamp falls on or after `since`. Runs in a few
    /// seconds over the full history — call it off-main.
    static func parse(since: Date) -> [String: TokenUsage] {
        var seen = Set<String>()
        var perModel: [String: TokenUsage] = [:]
        let decoder = JSONDecoder()

        for file in logFiles() {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                // Cheap pre-filter: skip non-assistant lines without decoding.
                guard line.contains("\"assistant\"") else { continue }
                guard let data = line.data(using: .utf8),
                      let turn = try? decoder.decode(AssistantTurn.self, from: data),
                      turn.type == "assistant",
                      let model = turn.message?.model,
                      let u = turn.message?.usage else { continue }

                // Window filter: drop turns recorded before the cutoff.
                guard let stamp = ISO8601.date(from: turn.timestamp), stamp >= since else { continue }

                if let requestId = turn.requestId {
                    guard seen.insert(requestId).inserted else { continue }
                }

                var usage = perModel[model] ?? .zero
                usage.input += u.input_tokens ?? 0
                usage.output += u.output_tokens ?? 0
                usage.cacheRead += u.cache_read_input_tokens ?? 0
                // Prefer the per-TTL split; fall back to treating an unsplit total
                // as the (default) 5-minute cache.
                if let split = u.cache_creation {
                    usage.cacheWrite5m += split.ephemeral_5m_input_tokens ?? 0
                    usage.cacheWrite1h += split.ephemeral_1h_input_tokens ?? 0
                } else {
                    usage.cacheWrite5m += u.cache_creation_input_tokens ?? 0
                }
                perModel[model] = usage
            }
        }
        return perModel
    }

    // MARK: - Minimal line shape

    private struct AssistantTurn: Decodable {
        let type: String?
        let requestId: String?
        let timestamp: String?
        let message: Message?
    }

    private struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_creation: CacheCreation?
    }

    private struct CacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }
}

/// Tolerant ISO8601 parsing for the transcript line timestamps, which include
/// fractional seconds and a `Z` offset (e.g. `2026-05-27T16:58:54.616Z`).
private enum ISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        if let date = withFractional.date(from: string) { return date }
        return plain.date(from: string)
    }
}
