//
//  AIMonitorWidget.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI
import WidgetKit

/// The Claude Code usage widget, served to both the Notification Center and the
/// desktop. Shows dashes until the host app bridges real usage data and triggers
/// a timeline reload.
struct AIMonitorWidget: Widget {
    private let kind = "AIMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIMonitorTimelineProvider()) { entry in
            AIMonitorWidgetView(entry: entry)
                .containerBackgroundCompat()
        }
        .configurationDisplayName("Claude Code")
        .description("Track your Claude Code usage limits and extra-usage charge.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension View {
    /// Uses the system's native widget fill — the same neutral material Stocks and
    /// the built-in widgets use — so it sits natively alongside them.
    func containerBackgroundCompat() -> some View {
        containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AIMonitorEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

/// Reads the latest snapshot the host app shared via the App-Group `SharedStore`
/// (the widget is sandboxed and can't fetch for itself), falling back to `.empty`
/// dashes when nothing has been stored yet. The host triggers a reload on every
/// successful fetch.
///
/// The timeline emits one entry per minute for the next hour — all carrying the
/// same snapshot but at increasing dates — so the "Updated N ago" label advances
/// on its own. That keeps it honest when the host can't fetch: the snapshot's
/// capture time is fixed, the entry date climbs, so the label keeps aging instead
/// of freezing. (A widget can't run a live timer, so stepping the entry dates is
/// the only way to make a minute-granular, seconds-free label tick.)
struct AIMonitorTimelineProvider: TimelineProvider {
    /// Minutes of self-advancing entries before WidgetKit asks for a fresh
    /// timeline; the host also reloads sooner on every successful fetch.
    private let horizonMinutes = 60

    func placeholder(in context: Context) -> AIMonitorEntry {
        AIMonitorEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (AIMonitorEntry) -> Void) {
        completion(AIMonitorEntry(date: Date(), snapshot: SharedStore.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIMonitorEntry>) -> Void) {
        let snapshot = SharedStore.load() ?? .empty
        let now = Date()
        let entries = (0...horizonMinutes).map { minute in
            AIMonitorEntry(date: now.addingTimeInterval(Double(minute) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Picks a layout for the current widget family, all driven by the same snapshot.
struct AIMonitorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AIMonitorEntry

    var body: some View {
        // The entry's date is the reference "now" for the freshness label, so it
        // advances minute by minute across the timeline entries.
        switch family {
        case .systemSmall:
            SmallWidgetContent(snapshot: entry.snapshot, now: entry.date)
        case .systemLarge:
            // Fill the (taller) large frame and pin the freshness footer to the
            // bottom; the dashboard itself stays top-aligned.
            DashboardView(snapshot: entry.snapshot, now: entry.date, pinFreshnessToBottom: true)
                .frame(maxWidth: .infinity)
        default:
            MediumWidgetContent(snapshot: entry.snapshot, now: entry.date)
        }
    }
}

/// The compact mascot + wordmark lockup used by the small and medium widgets, with
/// the freshness label tucked under the title.
private struct WidgetBrandLine: View {
    let snapshot: UsageSnapshot
    let now: Date
    /// Mascot pixel size; the medium widget asks for a slightly smaller critter.
    var pixel: CGFloat = 3.5
    /// When set, the extra-usage charge is shown on the right of the header.
    var trailingCost: Double? = nil
    /// Whether the freshness line keeps its "Updated " prefix; the tight small
    /// widget drops it and shows just the age.
    var showsUpdatedPrefix: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            PixelCritter(pixel: pixel)
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude Code")
                    .font(.caption)
                    .fontWeight(.semibold)
                FreshnessFooter(asOf: snapshot.asOf, now: now, showsPrefix: showsUpdatedPrefix)
            }
            Spacer(minLength: 6)
            if let trailingCost {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(UsageFormatting.extraUsage(trailingCost, currency: snapshot.currency, enabled: snapshot.extraUsageEnabled))
                        .font(.callout)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(ClaudePalette.clay)
                        .contentTransition(.numericText())
                    Text("Extra Usage")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Small family: the brand line, compact bars, the extra-usage charge, and a
/// freshness line.
private struct SmallWidgetContent: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetBrandLine(snapshot: snapshot, now: now, pixel: 3.9, showsUpdatedPrefix: false)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.gauges, id: \.title) { gauge in
                    LimitBar(gauge: gauge, compact: true, showsReset: false, now: snapshot.asOf)
                }
            }
            .padding(.top, 5)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(UsageFormatting.extraUsage(snapshot.extraUsageUSD, currency: snapshot.currency, enabled: snapshot.extraUsageEnabled))
                    .font(.callout)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(ClaudePalette.clay)
                    .contentTransition(.numericText())
                Text("Extra Usage")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Medium family: the brand line, the bars with a per-bar reset line, and the
/// extra-usage charge as a small bottom line.
private struct MediumWidgetContent: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetBrandLine(snapshot: snapshot, now: now, pixel: 4.2, trailingCost: snapshot.extraUsageUSD)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.gauges, id: \.title) { gauge in
                    LimitBar(gauge: gauge, compact: true, now: snapshot.asOf)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
    }
}

#Preview(as: .systemSmall) {
    AIMonitorWidget()
} timeline: {
    AIMonitorEntry(
        date: Date(),
        snapshot: UsageSnapshot(
            gauges: [
                LimitGauge(title: "Session", fraction: 0.62, resetsAt: Date().addingTimeInterval(7860)),
                LimitGauge(title: "Weekly", fraction: 0.88, resetsAt: Date().addingTimeInterval(277_200)),
            ],
            extraUsageUSD: 4.20, extraUsageLimitUSD: 200, extraUsageEnabled: true,
            estApiValueUSD: 182.5, asOf: Date()
        )
    )
}

#Preview(as: .systemMedium) {
    AIMonitorWidget()
} timeline: {
    AIMonitorEntry(
        date: Date(),
        snapshot: UsageSnapshot(
            gauges: [
                LimitGauge(title: "Session", fraction: 0.62, resetsAt: Date().addingTimeInterval(7860)),
                LimitGauge(title: "Weekly", fraction: 0.88, resetsAt: Date().addingTimeInterval(277_200)),
            ],
            extraUsageUSD: 4.20, extraUsageLimitUSD: 200, extraUsageEnabled: true,
            estApiValueUSD: 182.5, asOf: Date()
        )
    )
}

#Preview(as: .systemLarge) {
    AIMonitorWidget()
} timeline: {
    AIMonitorEntry(
        date: Date(),
        snapshot: UsageSnapshot(
            gauges: [
                LimitGauge(title: "Current session", fraction: 0.62, resetsAt: Date().addingTimeInterval(7860)),
                LimitGauge(title: "Weekly", fraction: 0.88, resetsAt: Date().addingTimeInterval(277_200)),
            ],
            extraUsageUSD: 4.20, extraUsageLimitUSD: 200, extraUsageEnabled: true,
            estApiValueUSD: 182.5, asOf: Date()
        )
    )
}
