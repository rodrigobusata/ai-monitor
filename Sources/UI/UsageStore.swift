//
//  UsageStore.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import AppKit
import Foundation
import SwiftUI
import WidgetKit

/// The app-owned engine that keeps usage current. Owned by `AIMonitorApp` so its
/// auto-refresh loop runs whether or not the menu-bar panel is open. Each fetch
/// goes through the shared `UsageService` (which authorizes with the app's own
/// OAuth token and never exposes it), then publishes the result to the panel,
/// mirrors it into the App-Group `SharedStore`, and nudges the widget to reload.
/// The token never reaches this layer. Also owns the sign-in / sign-out flow the
/// panel drives.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var phase: Phase = .idle
    /// The raw (pretty-printed) endpoint body from the last fetch, for inspection.
    @Published private(set) var lastResponse: String?
    /// Whether OAuth credentials exist — drives the panel's sign-in vs dashboard UI.
    @Published private(set) var isSignedIn: Bool
    /// True between "Sign in with Claude" (browser opened) and the pasted code.
    @Published private(set) var isAwaitingCode = false

    /// The in-flight sign-in attempt (PKCE verifier + state). Memory only.
    private var pendingSignIn: AnthropicOAuth.PendingSignIn?

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Seconds between automatic fetches. Set to the usage endpoint's per-token
    /// rate-limit floor (~180s) — the fastest cadence it tolerates without 429s.
    private let refreshInterval: TimeInterval = 180
    /// Never retry faster than this, even after a failure — respects the endpoint's
    /// ~180s rate-limit floor so a failing fetch doesn't hammer it into 429s.
    private let minRetryInterval: TimeInterval = 180

    private var loop: Task<Void, Never>?
    /// Consecutive failed fetches, used to back the retry cadence off gradually.
    private var consecutiveFailures = 0

    /// Cached inputs/result of the last local token-cost parse, so a refresh cycle
    /// only re-runs the multi-second scan when the logs (or the 30-day window)
    /// actually changed.
    private var cachedSignature: ClaudeCodeLogParser.Signature?
    private var cachedWindowStart: Date?
    private var cachedEstimate: Double?

    /// The result of a fetch, used to decide how long to wait before the next one.
    enum Outcome: Equatable {
        case success
        case failed(httpStatus: Int?)
    }

    init() {
        // Seed from the last snapshot shared with the widget so the panel shows
        // real, if slightly stale, data immediately on launch — before the first
        // live fetch completes.
        snapshot = SharedStore.load() ?? .empty
        isSignedIn = OAuthCredentialStore.load() != nil
        startAutoRefresh()
    }

    /// Starts the background auto-refresh loop. Idempotent — repeat calls are
    /// ignored, so it's safe to invoke from `init` and again from the UI.
    func startAutoRefresh() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Signed out: nothing to fetch — idle at the normal cadence.
                // (A successful sign-in triggers its own immediate refresh.)
                let outcome = self.isSignedIn ? await self.refresh() : Outcome.success
                try? await Task.sleep(for: .seconds(self.delay(after: outcome)))
            }
        }
    }

    // MARK: - Sign in / out

    /// Starts a sign-in: opens the approval page in the browser and waits for
    /// the user to paste back the code it displays.
    func beginSignIn() {
        let pending = AnthropicOAuth.beginSignIn()
        pendingSignIn = pending
        isAwaitingCode = true
        phase = .idle
        NSWorkspace.shared.open(pending.url)
    }

    /// Abandons the in-flight sign-in attempt.
    func cancelSignIn() {
        pendingSignIn = nil
        isAwaitingCode = false
        phase = .idle
    }

    /// Exchanges the pasted code for tokens, persists them in the app's keychain
    /// item, and kicks off an immediate usage fetch. Failures surface in `phase`.
    func completeSignIn(code: String) async {
        guard let pending = pendingSignIn else { return }
        phase = .loading
        do {
            let credentials = try await AnthropicOAuth.exchange(pastedCode: code, pending: pending)
            OAuthCredentialStore.save(credentials)
            pendingSignIn = nil
            isAwaitingCode = false
            isSignedIn = true
            await refresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Deletes the stored credentials and returns the panel to its signed-out
    /// state. The last snapshot stays visible (and keeps aging) until the next
    /// sign-in replaces it.
    func signOut() {
        OAuthCredentialStore.delete()
        isSignedIn = false
        lastResponse = nil
        phase = .idle
    }

    /// How long to wait before the next automatic fetch. A clean fetch waits the
    /// full interval; a failure retries sooner and backs off as failures pile up,
    /// while a 429 (rate-limited) eases all the way back to the normal interval.
    private func delay(after outcome: Outcome) -> TimeInterval {
        switch outcome {
        case .success:
            consecutiveFailures = 0
            return refreshInterval
        case .failed(let status):
            consecutiveFailures += 1
            if status == 429 { return refreshInterval }
            let backoff = minRetryInterval + 60 * Double(consecutiveFailures - 1)
            return min(refreshInterval, backoff)
        }
    }

    /// Fetches usage and updates the dashboard. On success it also shares the
    /// snapshot with the widget and triggers a timeline reload. Errors surface as
    /// an honest status message and leave the previous snapshot in place (the
    /// freshness label keeps aging, then flips to "stale"). Returns the outcome so
    /// the loop can pick the next retry cadence.
    @discardableResult
    func refresh() async -> Outcome {
        phase = .loading
        var outcome: Outcome = .success
        do {
            let result = try await UsageService.fetch()
            lastResponse = result.rawBody
            if let snapshot = result.snapshot {
                publish(snapshot.withEstApiValue(await estimatedApiValueUSD()))
                phase = .loaded
            } else {
                phase = .failed("HTTP \(result.status) — see response below")
                outcome = .failed(httpStatus: result.status)
            }
        } catch {
            lastResponse = nil
            phase = .failed(error.localizedDescription)
            outcome = .failed(httpStatus: nil)
        }
        return outcome
    }

    /// The estimated API list-price value of the last 30 days of local token
    /// usage. The cheap log-directory signature (and the window start) are checked
    /// first; the multi-second scan + pricing only run when something changed,
    /// off the main thread. Returns the cached value otherwise.
    private func estimatedApiValueUSD() async -> Double? {
        let windowStart = ClaudeCodeLogParser.startOfTrailing30Days()
        let signature = await Task.detached { ClaudeCodeLogParser.signature() }.value
        if signature == cachedSignature, windowStart == cachedWindowStart {
            return cachedEstimate
        }
        let perModel = await Task.detached { ClaudeCodeLogParser.parse(since: windowStart) }.value
        let estimate = TokenPricing.estimate(perModel)
        cachedSignature = signature
        cachedWindowStart = windowStart
        cachedEstimate = estimate
        return estimate
    }

    /// Publishes a snapshot to the panel, mirrors it to the widget's shared store,
    /// and triggers a widget reload.
    private func publish(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
