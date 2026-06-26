//
//  TokenUsage.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Token counts for a single model, summed from the local Claude Code transcript
/// logs over a time window. Cache-creation tokens are split by TTL because the
/// 5-minute and 1-hour ephemeral caches are billed at different multipliers.
/// Stays entirely on device.
struct TokenUsage: Equatable {
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite5m: Int
    var cacheWrite1h: Int

    static let zero = TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
}
