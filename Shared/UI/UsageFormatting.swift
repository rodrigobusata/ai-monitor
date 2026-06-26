//
//  UsageFormatting.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI

/// Presentation helpers shared by the menu-bar panel and the widget: gauge color
/// bands, the "just now / 2 min ago" freshness label, reset countdowns, and the
/// estimated-cost string. Kept free of any data source so both surfaces format
/// identically.
enum UsageFormatting {

    /// Placeholder shown wherever a value isn't known yet.
    static let dash = "—"

    /// A gauge's percentage as text, or a dash when unknown.
    static func percent(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? dash
    }

    // MARK: Freshness

    /// A compact "as of" label for a capture time, e.g. "just now", "2 min ago",
    /// "1 hr ago", or a dash when no data has been fetched. Minute-granular (never
    /// shows seconds). `now` is injectable so a `TimelineView` can re-evaluate it
    /// each minute.
    static func freshness(_ asOf: Date?, now: Date = Date()) -> String {
        guard let asOf else { return dash }
        let seconds = max(0, now.timeIntervalSince(asOf))
        switch seconds {
        case ..<60:
            return "just now"
        case ..<3600:
            let minutes = Int(seconds / 60)
            return "\(max(1, minutes)) min ago"
        case ..<86_400:
            let hours = Int(seconds / 3600)
            return "\(hours) hr ago"
        default:
            let days = Int(seconds / 86_400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    // MARK: Reset countdown

    /// The reset line for a gauge: a relative countdown when the reset is near
    /// (under a day, e.g. the session window → "Resets in 1 hr 23 min") and an
    /// absolute weekday + time when it's further out (e.g. the weekly window →
    /// "Resets Fri 9:00 PM"). Nil when the reset is unknown or already passed.
    static func resetLabel(_ resetsAt: Date?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        if seconds < 24 * 3600 {
            return resetCountdown(resetsAt, now: now)
        }
        return "Resets \(resetWeekdayTime.string(from: resetsAt))"
    }

    /// "Fri 9:00 PM" — weekday + time for a far-off reset.
    private static let resetWeekdayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    /// A short "Resets in 1 hr 23 min" style countdown, or nil when the reset time
    /// is unknown or already passed.
    static func resetCountdown(_ resetsAt: Date?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        let value: String
        if days > 0 {
            value = "\(days) d \(hours) hr"
        } else if hours > 0 {
            value = "\(hours) hr \(minutes) min"
        } else {
            value = "\(max(1, minutes)) min"
        }
        return "Resets in \(value)"
    }

    // MARK: Cost

    /// A charge formatted in the given currency (falling back to USD when the
    /// endpoint didn't report one), e.g. "$4,200.17", or a dash when unknown.
    static func cost(_ amount: Double?, currency: String? = nil) -> String {
        guard let amount else { return dash }
        return amount.formatted(.currency(code: currency ?? "USD"))
    }

    /// The extra-usage bar's bottom line: the monthly cap the charge counts toward,
    /// e.g. "of $200.00 monthly limit" — or nil when no cap is reported.
    static func monthlyLimit(_ limit: Double?, currency: String? = nil) -> String? {
        limit.map { "of \(cost($0, currency: currency)) monthly limit" }
    }

    /// The compact extra-usage figure the widgets show: "Off" when extra usage is
    /// disabled for the account, otherwise the formatted charge.
    static func extraUsage(_ amount: Double?, currency: String? = nil, enabled: Bool?) -> String {
        enabled == false ? "Off" : cost(amount, currency: currency)
    }
}
