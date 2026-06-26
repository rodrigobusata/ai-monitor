//
//  AIMonitorApp.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI

@main
struct AIMonitorApp: App {
    // Owned here (not in the panel) so the auto-refresh loop keeps running and
    // keeps the widget fed even while the menu-bar panel is closed.
    @StateObject private var store = UsageStore()

    var body: some Scene {
        // Menu-bar icon that opens the dashboard panel on click. The same usage
        // data also feeds the Notification Center / desktop widget via SharedStore.
        // The icon is the Claude Code mascot, drawn small so it reads in the bar.
        MenuBarExtra {
            MenuBarRootView(store: store)
        } label: {
            MenuBarMascot()
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar icon: the Claude Code mascot as a monochrome template.
///
/// Rendered as a *template* `NSImage` so the system tints it to match the menu bar
/// (white on a dark bar, black on a light one) — the standard look for menu-bar
/// glyphs. We rasterize the bare critter shape (eyes left as the path's transparent
/// holes, no dark fill) so the silhouette and eyes both read once tinted.
private struct MenuBarMascot: View {
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
            } else {
                Color.clear.frame(width: 19, height: 19)
            }
        }
        .onAppear { if icon == nil { icon = Self.render() } }
    }

    @MainActor private static func render() -> NSImage {
        let side: CGFloat = 19
        let shape = ClaudeCritterShape()
            .fill(.black, style: FillStyle(eoFill: true))
            .frame(width: side, height: side)
        let renderer = ImageRenderer(content: shape)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return NSImage() }
        image.isTemplate = true
        return image
    }
}
