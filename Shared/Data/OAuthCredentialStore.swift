//
//  OAuthCredentialStore.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/04/26.
//  © 2026 Rodrigo Busata.
//

import Foundation
import Security

/// Persists the app's own OAuth credentials in its own Keychain item. Unlike the
/// usage figures, these ARE secrets — they never go in the App-Group store, logs,
/// or files. The item is created by this app, so reading it back doesn't trigger
/// a keychain prompt (as long as the code signature stays stable — see the
/// `AIMonitorDev` signing identity notes in the README).
enum OAuthCredentialStore {

    private static let service = "com.aimonitor.app.oauth"
    private static let account = "anthropic"

    /// The stored credentials, or nil when the user hasn't signed in (or the
    /// blob can't be read/parsed — treated the same: signed out).
    static func load() -> AnthropicOAuth.Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AnthropicOAuth.Credentials.self, from: data)
    }

    /// Saves (replacing any previous item). A failed save is not fatal — the
    /// session just won't survive a relaunch — so no error is thrown.
    static func save(_ credentials: AnthropicOAuth.Credentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Removes the stored credentials (sign-out).
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
