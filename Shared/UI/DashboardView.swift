//
//  DashboardView.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI

/// The full usage dashboard: a mascot-led header, the limit bars (including the
/// extra-usage charge against its monthly cap), and the estimated API value as a
/// footer line. Used by the menu-bar panel and the large widget.
struct DashboardView: View {
    let snapshot: UsageSnapshot
    /// Reference time for the freshness label. `nil` in the panel (it ticks itself
    /// every minute); a widget passes its entry's date so the label advances across
    /// timeline entries.
    var now: Date? = nil
    /// When true, fills the available height and pushes the freshness footer to the
    /// bottom — used by the large widget, whose frame is taller than the content.
    /// The panel leaves it off so the view hugs its content.
    var pinFreshnessToBottom: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandHeader(asOf: snapshot.asOf, now: now)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(snapshot.gauges, id: \.title) { gauge in
                    LimitBar(gauge: gauge, now: snapshot.asOf)
                }
                extraUsageBar
            }

            if pinFreshnessToBottom { Spacer(minLength: 0) }

            apiValueFooter
        }
        .frame(maxHeight: pinFreshnessToBottom ? .infinity : nil, alignment: .top)
    }

    /// The extra-usage charge as a bar row beneath the limit bars: dollars spent
    /// up top, the monthly cap as the line under the bar ("of $200.00 monthly
    /// limit"), or "Off" over an empty bar when extra usage is disabled. Hidden
    /// until the endpoint reports anything.
    @ViewBuilder
    private var extraUsageBar: some View {
        if snapshot.extraUsageEnabled == false {
            LimitBar(
                gauge: LimitGauge(title: "Extra usage", fraction: nil, resetsAt: nil),
                valueText: "Off"
            )
        } else if snapshot.extraUsageUSD != nil || snapshot.extraUsageLimitUSD != nil {
            LimitBar(
                gauge: LimitGauge(title: "Extra usage", fraction: extraUsageFraction, resetsAt: nil),
                valueText: UsageFormatting.cost(snapshot.extraUsageUSD, currency: snapshot.currency),
                subtitleText: UsageFormatting.monthlyLimit(snapshot.extraUsageLimitUSD, currency: snapshot.currency)
            )
        }
    }

    /// The estimated API value as a small footer line — a hypothetical list-price
    /// figure, so it stays visually quieter than the bars.
    private var apiValueFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("API value")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(UsageFormatting.cost(snapshot.estApiValueUSD))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(ClaudePalette.clay)
                    // Roll the figure to its new value on refresh; .smooth = no bounce.
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.4), value: snapshot.estApiValueUSD)
            }
            Text("Est. last 30 days · not charged")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Spend as a fraction of the monthly cap; `nil` (no fill) when either side
    /// is unknown.
    private var extraUsageFraction: Double? {
        guard let used = snapshot.extraUsageUSD,
              let limit = snapshot.extraUsageLimitUSD,
              limit > 0 else { return nil }
        return used / limit
    }
}

/// The mascot + "Claude Code" wordmark, with the freshness label ("Updated 2 min
/// ago") sitting just beneath the title. Shared by the panel and the large widget.
struct BrandHeader: View {
    let asOf: Date?
    var now: Date? = nil

    var body: some View {
        HStack(spacing: 10) {
            PixelCritter(pixel: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Code")
                    .font(.headline)
                    .fontWeight(.semibold)
                FreshnessFooter(asOf: asOf, now: now)
            }
            Spacer(minLength: 8)
        }
    }
}

/// "Updated 2 min ago" footer driven by the snapshot's capture time, or a
/// "Not fetched yet" hint before any data has been loaded. Minute-granular (never
/// shows seconds). Once the data ages past `staleAfter` (e.g. fetches have been
/// failing) the clock icon turns into an amber warning triangle — an honest signal
/// that works in both surfaces, since the label keeps aging on its own.
///
/// When `now` is `nil` (the panel) a `TimelineView` re-evaluates the label every
/// minute, so it ticks up on its own. When `now` is supplied (a widget entry's
/// date) it renders once for that instant — the widget advances the label by
/// stepping its timeline entries, since it can't run a live timer.
struct FreshnessFooter: View {
    let asOf: Date?
    var now: Date? = nil
    /// When false, the label drops the "Updated " prefix and shows just the age
    /// (e.g. "1 min ago") — used by the tight small widget.
    var showsPrefix: Bool = true

    /// Age past which the data is shown as stale (≈3 missed 300s refresh cycles).
    private let staleAfter: TimeInterval = 15 * 60

    var body: some View {
        if let asOf {
            if let now {
                FreshnessLabel(asOf: asOf, now: now, staleAfter: staleAfter, showsPrefix: showsPrefix)
            } else {
                TimelineView(.periodic(from: asOf, by: 60)) { context in
                    FreshnessLabel(asOf: asOf, now: context.date, staleAfter: staleAfter, showsPrefix: showsPrefix)
                }
            }
        } else {
            FreshnessLabel(asOf: nil, now: nil, staleAfter: staleAfter, showsPrefix: showsPrefix)
        }
    }
}

/// One rendered freshness line: clock + "Updated N ago", flipping the clock to an
/// amber warning triangle once the data is too old, or "Not fetched yet" when empty.
private struct FreshnessLabel: View {
    let asOf: Date?
    let now: Date?
    let staleAfter: TimeInterval
    var showsPrefix: Bool = true

    private var isStale: Bool {
        guard let asOf, let now else { return false }
        return now.timeIntervalSince(asOf) > staleAfter
    }

    private var text: String {
        guard let asOf, let now else { return "Not fetched yet" }
        let age = UsageFormatting.freshness(asOf, now: now)
        return showsPrefix ? "Updated \(age)" : age
    }

    var body: some View {
        HStack(spacing: 4) {
            // No icon in the normal "Updated …" state; only an amber warning shows
            // once the data has gone stale.
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
            }
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                // Roll the age digits to their new value as the label ticks.
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: text)
        }
        .font(.caption)
        .foregroundStyle(isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
    }
}

#Preview {
    DashboardView(
        snapshot: UsageSnapshot(
            gauges: [
                LimitGauge(title: "Current session", fraction: 0.62, resetsAt: Date().addingTimeInterval(7860)),
                LimitGauge(title: "Weekly", fraction: 0.88, resetsAt: Date().addingTimeInterval(277_200)),
            ],
            extraUsageUSD: 4.20,
            extraUsageLimitUSD: 200,
            extraUsageEnabled: true,
            estApiValueUSD: 182.50,
            asOf: Date()
        )
    )
    .padding(20)
    .frame(width: 320)
    .background(ClaudePalette.surface(.light))
}

#Preview("Extra usage off") {
    DashboardView(
        snapshot: UsageSnapshot(
            gauges: [
                LimitGauge(title: "Current session", fraction: 0.62, resetsAt: Date().addingTimeInterval(7860)),
                LimitGauge(title: "Weekly", fraction: 0.88, resetsAt: Date().addingTimeInterval(277_200)),
            ],
            extraUsageUSD: 0,
            extraUsageEnabled: false,
            estApiValueUSD: 182.50,
            asOf: Date()
        )
    )
    .padding(20)
    .frame(width: 320)
    .background(ClaudePalette.surface(.light))
}
