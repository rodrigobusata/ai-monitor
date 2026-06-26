//
//  UsageModels.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// A single rolling usage limit (e.g. the 5-hour session window or the weekly
/// window): how much of it has been consumed and when it resets. A `nil`
/// `fraction` means the value isn't known yet and the UI shows a dash.
struct LimitGauge: Equatable, Codable {
    /// Short label shown above the bar (e.g. "5-hour", "Daily", "Weekly").
    let title: String
    /// Fraction of the window consumed, clamped to `0...1`; `nil` when unknown.
    let fraction: Double?
    /// When the window rolls over and frees up capacity, if known.
    let resetsAt: Date?

    init(title: String, fraction: Double?, resetsAt: Date?) {
        self.title = title
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.resetsAt = resetsAt
    }

    /// `fraction` as a whole-number percentage (0...100), or `nil` when unknown.
    var percent: Int? {
        fraction.map { Int(($0 * 100).rounded()) }
    }
}

/// A point-in-time view of Claude Code usage: the rolling limit windows the usage
/// endpoint reports (5-hour + weekly), the cost of any usage beyond the plan, and
/// the moment the data was captured (for the freshness label). Numeric fields are
/// optional so the UI can show dashes until real data arrives.
struct UsageSnapshot: Equatable, Codable {
    /// The limit windows in display order.
    let gauges: [LimitGauge]
    /// What you're charged for usage that exceeds the plan ("extra usage"), in USD;
    /// `nil` when unknown.
    let extraUsageUSD: Double?
    /// The monthly cap on extra-usage spend, in the charge currency; `nil` when
    /// unknown.
    let extraUsageLimitUSD: Double?
    /// Whether extra usage (pay-as-you-go beyond the plan) is turned on for the
    /// account; `nil` when unknown.
    let extraUsageEnabled: Bool?
    /// ISO 4217 currency code the endpoint reports for the charge (e.g. "USD");
    /// `nil` when unknown — formatting falls back to USD.
    let currency: String?
    /// Estimated API list-price value of the last 30 days of local token usage,
    /// in USD — what those tokens *would* cost on pay-as-you-go, not money charged.
    /// `nil` until the local logs have been parsed.
    let estApiValueUSD: Double?
    /// When this snapshot was produced; `nil` before any data has been fetched.
    let asOf: Date?

    init(
        gauges: [LimitGauge],
        extraUsageUSD: Double?,
        extraUsageLimitUSD: Double? = nil,
        extraUsageEnabled: Bool? = nil,
        currency: String? = nil,
        estApiValueUSD: Double?,
        asOf: Date?
    ) {
        self.gauges = gauges
        self.extraUsageUSD = extraUsageUSD
        self.extraUsageLimitUSD = extraUsageLimitUSD
        self.extraUsageEnabled = extraUsageEnabled
        self.currency = currency
        self.estApiValueUSD = estApiValueUSD
        self.asOf = asOf
    }

    /// The placeholder shown before any real data is fetched: the windows the
    /// endpoint reports, with no values, so every figure renders as a dash.
    static let empty = UsageSnapshot(
        gauges: [
            LimitGauge(title: "Current session", fraction: nil, resetsAt: nil),
            LimitGauge(title: "Weekly", fraction: nil, resetsAt: nil),
        ],
        extraUsageUSD: nil,
        estApiValueUSD: nil,
        asOf: nil
    )

    /// A copy of this snapshot with the estimated API value replaced — used to merge
    /// the locally-parsed token cost into the endpoint-derived snapshot.
    func withEstApiValue(_ usd: Double?) -> UsageSnapshot {
        UsageSnapshot(
            gauges: gauges,
            extraUsageUSD: extraUsageUSD,
            extraUsageLimitUSD: extraUsageLimitUSD,
            extraUsageEnabled: extraUsageEnabled,
            currency: currency,
            estApiValueUSD: usd,
            asOf: asOf
        )
    }
}
