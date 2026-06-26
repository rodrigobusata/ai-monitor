//
//  SharedStore.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import Foundation

/// The bridge between the host app and the sandboxed widget. The widget can't
/// reach the network or the keychain, so the host fetches usage and stashes the
/// latest `UsageSnapshot` in a shared App-Group store; the widget reads it back.
///
/// Backed by `UserDefaults(suiteName:)` against the `group.com.aimonitor.app`
/// App Group, which both targets carry as an entitlement. The snapshot holds no
/// secrets — just the limit percentages, reset times, and extra-usage charge —
/// so it's safe to persist here (unlike the OAuth token, which never leaves the
/// fetch call).
enum SharedStore {
    /// The App Group both the app and the widget declare in their entitlements.
    /// Its shared container lives at `~/Library/Group Containers/<id>`.
    static let appGroupID = "group.com.aimonitor.app"

    private static let snapshotKey = "latestUsageSnapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Persists the latest snapshot for the widget to pick up. A no-op if the
    /// App-Group container is unavailable (e.g. the entitlement didn't take).
    static func save(_ snapshot: UsageSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    /// The last snapshot the host shared, or `nil` if nothing has been stored
    /// (or the container is unavailable). Callers fall back to `.empty`.
    static func load() -> UsageSnapshot? {
        guard let defaults, let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
