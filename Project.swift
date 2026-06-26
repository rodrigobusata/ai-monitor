import ProjectDescription

// AI Monitor — macOS app that monitors AI tool usage (starting with Claude Code).
// Two targets:
//   • AIMonitor        — the menu-bar host app (LSUIElement, opens a panel on click).
//   • AIMonitorWidget  — a WidgetKit extension serving both the Notification Center
//                        and the desktop. One extension covers both surfaces.
// UI is still placeholder in this phase; mocked then live data arrive later.
//
// NOTE on argument order: ProjectDescription's `.target(...)` enforces a fixed
// parameter order (… sources, resources, entitlements, scripts, dependencies,
// settings …). Out-of-order args make `tuist generate` fail — keep this order.

let project = Project(
    name: "AIMonitor",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    // Both targets carry the `group.com.aimonitor.app` App-Group entitlement (the
    // host writes the usage snapshot, the sandboxed widget reads it). Xcode's build
    // system refuses to sign an app-groups entitlement without a provisioning
    // profile / dev team — which this personal, account-less project doesn't have.
    // So we turn Xcode's signing OFF and adhoc re-sign the bundle ourselves in the
    // install step (see the scheme post-action). macOS honors app-groups under an
    // adhoc signature, so the shared container works without any Apple account.
    settings: .settings(base: ["CODE_SIGNING_ALLOWED": "NO"]),
    targets: [
        .target(
            name: "AIMonitor",
            destinations: .macOS,
            product: .app,
            bundleId: "com.aimonitor.app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                // Menu-bar app: no Dock icon, no main window by default.
                "LSUIElement": true,
                "CFBundleDisplayName": "AI Monitor",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
            ]),
            // Shared/** holds the usage model, mock provider, and reusable UI
            // (dashboard, bars, badge) compiled into both the app and the widget.
            sources: ["Sources/**", "Shared/**"],
            // Host stays non-sandboxed; this only adds the App-Group entitlement
            // so it can share the usage snapshot with the sandboxed widget.
            entitlements: .file(path: "Sources/AIMonitor.entitlements"),
            dependencies: [
                // Embeds the widget extension inside the app bundle.
                .target(name: "AIMonitorWidget"),
            ]
        ),
        .target(
            name: "AIMonitorWidget",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "com.aimonitor.app.widget",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "AI Monitor",
                // Must match the host app's version, else embedding warns.
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["Widget/**", "Shared/**"],
            // macOS app extensions must be sandboxed (app-sandbox entitlement) or
            // pkd silently refuses to register the widget and it never appears in
            // the gallery. The entitlements file sets CODE_SIGN_ENTITLEMENTS.
            entitlements: .file(path: "Widget/AIMonitorWidget.entitlements"),
            dependencies: []
        ),
    ],
    schemes: [
        .scheme(
            name: "AIMonitor",
            shared: true,
            buildAction: .buildAction(
                targets: ["AIMonitor"],
                // Runs AFTER the build. Xcode signing is OFF (see project settings),
                // so this step adhoc re-signs the bundle with the App-Group
                // entitlements — widget appex first, then the host app so its seal
                // captures the appex — then installs the validly-signed copy into
                // /Applications. macOS discovers the WidgetKit extension far more
                // reliably from /Applications than from DerivedData, and an adhoc
                // signature counts as valid for local registration.
                // NOTE: scheme post-actions only run for Xcode-GUI builds; a plain
                // `xcodebuild build` skips them, so the command-line loop re-signs
                // and installs by hand (the exact steps are in the README).
                postActions: [
                    .executionAction(
                        title: "Re-sign + install to /Applications",
                        // Signs with the stable self-signed "AIMonitorDev" identity
                        // (not adhoc). A stable identity gives the bundle a constant
                        // keychain designated requirement, so access to the app's own
                        // keychain item (the OAuth tokens) survives rebuilds — adhoc's
                        // cdhash changes every build and would lose that access.
                        // Create the cert once via Keychain Access
                        // (Certificate Assistant → Code Signing, name "AIMonitorDev").
                        scriptText: """
                        if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$FULL_PRODUCT_NAME" ]; then
                            APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
                            APPEX="$APP/Contents/PlugIns/AIMonitorWidget.appex"
                            codesign --force --sign "AIMonitorDev" --entitlements "$SRCROOT/Widget/AIMonitorWidget.entitlements" "$APPEX"
                            codesign --force --sign "AIMonitorDev" --entitlements "$SRCROOT/Sources/AIMonitor.entitlements" "$APP"
                            rm -rf "/Applications/$FULL_PRODUCT_NAME"
                            cp -R "$APP" "/Applications/"
                        fi
                        """,
                        target: "AIMonitor"
                    ),
                ]
            ),
            runAction: .runAction(executable: "AIMonitor")
        ),
    ]
)
