//
//  TokenPricing.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Turns local token tallies into an estimated dollar figure at Anthropic's public
/// **API list prices** — what those tokens *would* have cost on pay-as-you-go. This
/// is a hypothetical "value received" number, not money charged; it is deliberately
/// kept distinct from the plan's real "extra usage" charge.
///
/// The price table is the part that ages: models get added and rates change, so it
/// lives in one place with the date it was last verified. A model whose family we
/// don't recognize is left out of the total (an honest under-estimate) rather than
/// guessed at.
enum TokenPricing {

    /// Per-million-token USD rates for one model family.
    struct Rates {
        let input: Double
        let output: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
        let cacheRead: Double
    }

    /// Anthropic API list prices, USD per 1M tokens. Verified 2026-06-01.
    /// Cache writes bill at 1.25x (5-minute TTL) / 2x (1-hour TTL) of input; cache
    /// reads at 0.1x. Matched by family substring so a new point release still maps.
    private static let opus = Rates(input: 15, output: 75, cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50)
    private static let sonnet = Rates(input: 3, output: 15, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30)
    private static let haiku = Rates(input: 1, output: 5, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.10)

    /// Maps a model id (e.g. `claude-opus-4-8`) to its rates, or `nil` when the
    /// family isn't one we price.
    static func rates(for modelID: String) -> Rates? {
        let id = modelID.lowercased()
        if id.contains("opus") { return opus }
        if id.contains("sonnet") { return sonnet }
        if id.contains("haiku") { return haiku }
        return nil
    }

    /// Sums the list-price cost (USD) across every model in the tally. Tokens from
    /// unrecognized model families are skipped.
    static func estimate(_ perModel: [String: TokenUsage]) -> Double {
        perModel.reduce(0) { total, entry in
            guard let rates = rates(for: entry.key) else { return total }
            return total + cost(entry.value, at: rates)
        }
    }

    private static func cost(_ usage: TokenUsage, at rates: Rates) -> Double {
        let perMillion =
            Double(usage.input) * rates.input
            + Double(usage.output) * rates.output
            + Double(usage.cacheRead) * rates.cacheRead
            + Double(usage.cacheWrite5m) * rates.cacheWrite5m
            + Double(usage.cacheWrite1h) * rates.cacheWrite1h
        return perMillion / 1_000_000
    }
}
