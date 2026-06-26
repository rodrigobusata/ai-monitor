//
//  UsageEndpointResponse.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// Decodes the usage endpoint's JSON and maps it onto a `UsageSnapshot`.
///
/// The payload also carries several codenamed keys (`cinder_cove`, `tangelo`,
/// `iguana_necktie`, model-specific `seven_day_*`, …) that are null in practice;
/// we read only the windows we display and ignore the rest, so an added/renamed
/// key won't break decoding.
struct UsageEndpointResponse: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
    }

    /// A rolling limit window: percent consumed + when it resets.
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    /// Pay-as-you-go usage beyond the plan. `usedCredits` / `monthlyLimit` are in
    /// the smallest currency unit (cents for USD) — confirm once a non-zero value
    /// appears, since a `0` can't disambiguate cents from dollars.
    struct ExtraUsage: Decodable {
        let currency: String?
        let isEnabled: Bool?
        let usedCredits: Double?
        let monthlyLimit: Double?

        enum CodingKeys: String, CodingKey {
            case currency
            case isEnabled = "is_enabled"
            case usedCredits = "used_credits"
            case monthlyLimit = "monthly_limit"
        }
    }

    static func decode(_ data: Data) throws -> UsageEndpointResponse {
        try JSONDecoder().decode(UsageEndpointResponse.self, from: data)
    }

    /// Builds the dashboard snapshot. `asOf` is the fetch time (drives freshness).
    func toSnapshot(asOf: Date) -> UsageSnapshot {
        UsageSnapshot(
            gauges: [
                gauge(title: "Current session", from: fiveHour),
                gauge(title: "Weekly", from: sevenDay),
            ],
            // Charged extra usage and its monthly cap, cents -> dollars.
            extraUsageUSD: extraUsage?.usedCredits.map { $0 / 100 },
            extraUsageLimitUSD: extraUsage?.monthlyLimit.map { $0 / 100 },
            extraUsageEnabled: extraUsage?.isEnabled,
            currency: extraUsage?.currency,
            // Locally parsed; merged in by the store after this maps the endpoint.
            estApiValueUSD: nil,
            asOf: asOf
        )
    }

    private func gauge(title: String, from window: Window?) -> LimitGauge {
        LimitGauge(
            title: title,
            // utilization is a 0...100 percentage; the gauge wants a 0...1 fraction.
            fraction: window?.utilization.map { $0 / 100 },
            resetsAt: ISO8601.date(from: window?.resetsAt)
        )
    }
}

/// Tolerant ISO8601 parsing for the endpoint's reset timestamps, which include
/// fractional seconds and a `+00:00` offset (e.g. `2026-06-01T19:20:00.518638+00:00`).
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
        if let date = plain.date(from: string) { return date }
        // Some OS versions reject 6-digit microseconds — strip fractional seconds.
        if let range = string.range(of: #"\.\d+"#, options: .regularExpression) {
            var trimmed = string
            trimmed.removeSubrange(range)
            return plain.date(from: trimmed)
        }
        return nil
    }
}
