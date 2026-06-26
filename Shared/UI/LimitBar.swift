//
//  LimitBar.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI
import WidgetKit

/// One usage limit rendered as a labeled progress bar: title + percentage on top,
/// a warm Claude-banded fill below, and a "Resets in …" countdown.
/// Shared by the menu-bar panel and every widget family.
struct LimitBar: View {
    let gauge: LimitGauge
    /// Tightens spacing and fonts for space-constrained surfaces (small/medium
    /// widgets).
    var compact: Bool = false
    /// Whether to show the "Resets in …" countdown. Off on the small widget, which
    /// is too tight to spare the line.
    var showsReset: Bool = true
    /// Reference "now" for the reset countdown; defaults to the current date when
    /// the snapshot hasn't been captured yet (`nil`).
    var now: Date?
    /// When set, replaces the percentage with a custom trailing value — the
    /// extra-usage row uses it to show "$4.20" (or "Off").
    var valueText: String? = nil
    /// When set, shown under the bar in place of the reset countdown — the
    /// extra-usage row uses it for "of $200.00 monthly limit".
    var subtitleText: String? = nil

    @Environment(\.colorScheme) private var scheme
    /// In a tinted widget (`.accented` / `.vibrant`) the warm band colors collapse
    /// to one tone, so the fill vanishes against the track. There we drop the colors
    /// and convey the bar by opacity instead (a solid fill over a faint groove).
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var tint: Color { ClaudePalette.band(for: gauge.fraction) }
    private var isFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.title)
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(valueText ?? UsageFormatting.percent(gauge.percent))
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(isFullColor ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
                    .monospacedDigit()
                    // On refresh the value rolls to its new figure rather than
                    // snapping; .smooth is a spring with no overshoot, so no bounce.
                    .contentTransition(.numericText(value: Double(gauge.percent ?? 0)))
                    .animation(.smooth(duration: 0.4), value: valueText ?? UsageFormatting.percent(gauge.percent))
            }

            track

            if let line = subtitleText ?? resetLine {
                Text(line)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.tertiary)
                    // Roll the countdown digits to their new value on refresh.
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.4), value: line)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gauge.title)
        .accessibilityValue(valueText ?? gauge.percent.map { "\($0) percent used" } ?? "no data yet")
    }

    /// The "Resets in …" countdown shown when no subtitle overrides the bottom line.
    private var resetLine: String? {
        showsReset ? UsageFormatting.resetLabel(gauge.resetsAt, now: now ?? Date()) : nil
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackStyle)
                Capsule()
                    .fill(fillStyle)
                    .frame(width: fillWidth(in: proxy.size))
                    .shadow(color: isFullColor ? tint.opacity(0.45) : .clear, radius: 2, y: 0.5)
                    // Grow/shrink the fill to its new width on refresh; non-bouncy.
                    .animation(.smooth(duration: 0.5), value: gauge.fraction)
            }
        }
        .frame(height: compact ? 6 : 8)
    }

    /// Fill width for the consumed portion. Never narrower than the bar height
    /// (except at zero), so tiny fractions still render as a round capsule dot
    /// instead of a squashed square edge.
    private func fillWidth(in size: CGSize) -> CGFloat {
        let width = size.width * (gauge.fraction ?? 0)
        return width > 0 ? max(size.height, width) : 0
    }

    /// The empty groove: a warm track in full color, a faint primary in tinted modes.
    private var trackStyle: AnyShapeStyle {
        isFullColor
            ? AnyShapeStyle(ClaudePalette.track(scheme))
            : AnyShapeStyle(Color.primary.opacity(0.18))
    }

    /// The consumed portion: a warm band gradient in full color; a solid, fully
    /// opaque primary in tinted modes so it tints cleanly and stays legible.
    private var fillStyle: AnyShapeStyle {
        isFullColor
            ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(Color.primary)
    }
}

#Preview {
    VStack(spacing: 16) {
        LimitBar(gauge: LimitGauge(title: "Current session", fraction: 0.62, resetsAt: Date().addingTimeInterval(7860)))
        LimitBar(gauge: LimitGauge(title: "Weekly", fraction: 0.84, resetsAt: Date().addingTimeInterval(277_200)))
        LimitBar(gauge: LimitGauge(title: "Current session", fraction: 0.62, resetsAt: nil), compact: true)
        LimitBar(
            gauge: LimitGauge(title: "Extra usage", fraction: 0.021, resetsAt: nil),
            valueText: UsageFormatting.cost(4.20),
            subtitleText: UsageFormatting.monthlyLimit(200)
        )
    }
    .padding()
    .frame(width: 280)
    .background(ClaudePalette.surface(.light))
}
