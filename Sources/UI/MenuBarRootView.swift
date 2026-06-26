//
//  MenuBarRootView.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI

/// Panel shown from the menu-bar icon. Renders the usage dashboard from the
/// app-owned `UsageStore` (which auto-refreshes in the background), offers a
/// "Refresh usage" button to pull live data on demand, and hosts the
/// sign-in / sign-out flow.
struct MenuBarRootView: View {
    @ObservedObject var store: UsageStore
    @State private var showRawResponse = false
    @State private var pastedCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardView(snapshot: store.snapshot)

            Divider().overlay(ClaudePalette.clay.opacity(0.12))

            if store.isSignedIn {
                fetchRow
            } else {
                signInSection
            }

            if store.isSignedIn, let response = store.lastResponse {
                Toggle("Show raw response", isOn: $showRawResponse)
                    .toggleStyle(.switch)
                    .tint(ClaudePalette.clay)
                    .controlSize(.mini)
                    .font(.caption)

                if showRawResponse {
                    ResponseInspector(text: response)
                }
            }

            Divider().overlay(ClaudePalette.clay.opacity(0.12))

            HStack {
                Text("Also in Notification Center & on your desktop.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if store.isSignedIn {
                    Button("Sign out") {
                        store.signOut()
                    }
                    .buttonStyle(.bordered)
                    .tint(ClaudePalette.clay)
                    .controlSize(.small)
                }
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.bordered)
                .tint(ClaudePalette.clay)
                .controlSize(.small)
                .keyboardShortcut("q")
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private var fetchRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh usage", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(ClaudePalette.clay)
            .controlSize(.small)
            .disabled(store.phase == .loading)

            if store.phase == .loading {
                ProgressView().controlSize(.small)
            }

            Spacer(minLength: 4)
        }

        statusLabel
    }

    /// Signed-out UI: a button that opens the Claude approval page, then a field
    /// to paste back the code the page displays.
    @ViewBuilder
    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isAwaitingCode {
                Text("Approve in the browser, then paste the code shown there:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Paste code…", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await store.completeSignIn(code: pastedCode)
                            if store.isSignedIn { pastedCode = "" }
                        }
                    } label: {
                        Label("Complete sign-in", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ClaudePalette.clay)
                    .controlSize(.small)
                    .disabled(
                        pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || store.phase == .loading
                    )

                    Button("Cancel") {
                        store.cancelSignIn()
                        pastedCode = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if store.phase == .loading {
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                Text("Sign in with your Claude account to load usage — a browser window opens to approve access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    store.beginSignIn()
                } label: {
                    Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaudePalette.clay)
                .controlSize(.small)
            }

            if case .failed(let message) = store.phase {
                Label(message, systemImage: "xmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.phase {
        case .idle:
            Text("Signed in with your Claude account — the token stays in your keychain.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loading:
            Text("Contacting the usage endpoint…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .loaded:
            EmptyView()
        case .failed(let message):
            Label(message, systemImage: "xmark.circle")
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Scrollable, monospaced view of the raw endpoint response — an inspection aid,
/// toggled from the panel.
private struct ResponseInspector: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 160)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(ClaudePalette.track(scheme).opacity(0.5)))
    }
}

#Preview {
    MenuBarRootView(store: UsageStore())
}
