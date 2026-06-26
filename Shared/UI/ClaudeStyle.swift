//
//  ClaudeStyle.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI
import WidgetKit

/// Claude Code's visual identity, shared by the menu-bar panel and every widget
/// family: the warm clay/terracotta brand color, the paper-and-night surfaces, and
/// the usage-band scale. Keeping it here means both surfaces look identical and the
/// whole app shifts on-brand from one place.
enum ClaudePalette {

    // MARK: Brand

    /// The terracotta clay of the Claude Code mascot — the primary brand color.
    static let clay = Color(hex: 0xC15F3C)
    /// A brighter coral used for glints and the live-status dot.
    static let coral = Color(hex: 0xD97757)
    /// The near-black warm ink used for the mascot's eyes and dark text.
    static let ink = Color(hex: 0x2B2A27)

    // MARK: Usage bands

    /// Tint for a limit bar by how full it is — a warm escalation that stays in the
    /// Claude family: clay while there's headroom, amber as it tightens, red when
    /// it's nearly spent. Unknown values render a muted warm gray.
    static func band(for fraction: Double?) -> Color {
        guard let fraction else { return Color(hex: 0x9A968E) }
        switch fraction {
        case ..<0.75: return clay
        case ..<0.90: return Color(hex: 0xE0922F)
        default: return Color(hex: 0xC5402B)
        }
    }

    // MARK: Surfaces

    /// The empty portion of a limit track — a warm, scheme-aware groove.
    static func track(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x3A3733) : Color(hex: 0xE7E3D9)
    }

    /// The card / panel fill: warm paper in light mode, warm charcoal in dark.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x262420) : Color(hex: 0xFAF9F5)
    }

    /// A gentle top-to-bottom wash used behind the widgets so they read as a single
    /// warm Claude Code surface rather than a flat tile.
    static func backdrop(_ scheme: ColorScheme) -> LinearGradient {
        let colors = scheme == .dark
            ? [Color(hex: 0x2C2925), Color(hex: 0x1C1A17)]
            : [Color(hex: 0xFBFAF6), Color(hex: 0xF1EEE4)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    /// Builds a color from a packed `0xRRGGBB` literal — keeps the palette readable.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The Claude Code mascot: the official "Claude Code" glyph rendered straight from
/// its vector path — a boxy coral critter with a full-width arm band, four legs, and
/// two eyes. Pure vector so it stays crisp at any size and needs no image asset
/// (works inside the sandboxed widget too).
struct PixelCritter: View {
    /// A scale unit; the critter is laid out 7 units wide, matching its footprint.
    var pixel: CGFloat = 6

    /// In a desktop/Notification Center widget the system can render everything in a
    /// single tint (`.accented` / `.vibrant`), which flattens the dark eyes into the
    /// same tone as the body and makes them vanish. In those modes we leave the eyes
    /// as the path's transparent holes so they read against the single-tone body; in
    /// full color we fill those holes with dark ink for the iconic look.
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var side: CGFloat { pixel * 7 }

    var body: some View {
        ClaudeCritterShape()
            .fill(ClaudePalette.coral, style: FillStyle(eoFill: true))
            .frame(width: side, height: side)
            .overlay { if renderingMode == .fullColor { eyes } }
            // A whisper of shadow lifts the critter off the surface.
            .shadow(color: ClaudePalette.ink.opacity(0.18), radius: pixel * 0.18, y: pixel * 0.12)
    }

    /// The two dark eyes, dropped into the path's eye holes in full color. Positions
    /// come straight from the icon's 24-unit viewBox.
    private var eyes: some View {
        let unit = side / 24
        return ZStack {
            eye(x: 6, width: 1.488, unit: unit)
            eye(x: 16.51, width: 1.49, unit: unit)
        }
        .frame(width: side, height: side)
    }

    private func eye(x: CGFloat, width: CGFloat, unit: CGFloat) -> some View {
        Rectangle()
            .fill(ClaudePalette.ink)
            .frame(width: width * unit, height: 2.847 * unit)
            .position(x: (x + width / 2) * unit, y: (8.102 + 2.847 / 2) * unit)
    }
}

/// The "Claude Code" icon as a `Shape`, traced from its SVG path on a 24×24 grid:
/// the body outline plus two eye rectangles, filled even-odd so the eyes are holes.
struct ClaudeCritterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }

        var path = Path()
        path.move(to: point(Self.outline[0].0, Self.outline[0].1))
        for vertex in Self.outline.dropFirst() {
            path.addLine(to: point(vertex.0, vertex.1))
        }
        path.closeSubpath()

        // Eye holes — even-odd fill turns these into cut-outs.
        path.addRect(CGRect(x: rect.minX + 6 * unit, y: rect.minY + 8.102 * unit,
                            width: 1.488 * unit, height: 2.847 * unit))
        path.addRect(CGRect(x: rect.minX + 16.51 * unit, y: rect.minY + 8.102 * unit,
                            width: 1.49 * unit, height: 2.847 * unit))
        return path
    }

    /// The body's outer boundary, in viewBox coordinates, walked clockwise.
    private static let outline: [(CGFloat, CGFloat)] = [
        (20.998, 10.949), (24, 10.949), (24, 14.051), (21, 14.051), (21, 17.079),
        (19.513, 17.079), (19.513, 20), (18, 20), (18, 17.079), (16.513, 17.079),
        (16.513, 20), (15, 20), (15, 17.079), (9, 17.079), (9, 20), (7.488, 20),
        (7.488, 17.079), (6, 17.079), (6, 20), (4.487, 20), (4.487, 17.079),
        (3, 17.079), (3, 14.05), (0, 14.05), (0, 10.95), (3, 10.95), (3, 5),
        (20.998, 5),
    ]
}

#Preview {
    HStack(spacing: 24) {
        PixelCritter(pixel: 10)
        PixelCritter(pixel: 20)
    }
    .padding(40)
    .background(ClaudePalette.backdrop(.light))
}
