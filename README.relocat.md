# Relocat Fork Notes

This file documents Relocat-specific usage and integration details for
this vendored fork. The upstream README.md documents the plugin's
general behavior.

## FSI-81: Scene-based iOS lifecycle integration

On iOS 13+ with scene-based hosts (Flutter 3.11+ default), the share
extension's redirect URL is delivered to `UISceneDelegate`, not to
`UIApplicationDelegate`. The upstream plugin only observes AppDelegate
callbacks, so scene-based hosts silently miss share intents.

This fork exposes two static forwarding functions on
`SwiftFlutterSharingIntentPlugin`:

- `handleSceneURLContexts(_ urlContexts: Set<UIOpenURLContext>)`
- `handleSceneUserActivity(_ userActivity: NSUserActivity)`

Host apps with scene-based lifecycles must forward the relevant
UIScene delegate callbacks to these methods, for example from the
host app's `ios/Runner/SceneDelegate.swift`:

    import UIKit
    import flutter_sharing_intent

    class SceneDelegate: UIResponder, UIWindowSceneDelegate {
        func scene(_ scene: UIScene,
                   willConnectTo session: UISceneSession,
                   options connectionOptions: UIScene.ConnectionOptions) {
            SwiftFlutterSharingIntentPlugin.handleSceneURLContexts(
                connectionOptions.urlContexts)
            if let activity = connectionOptions.userActivities.first {
                SwiftFlutterSharingIntentPlugin.handleSceneUserActivity(activity)
            }
        }

        func scene(_ scene: UIScene,
                   openURLContexts URLContexts: Set<UIOpenURLContext>) {
            SwiftFlutterSharingIntentPlugin.handleSceneURLContexts(URLContexts)
        }

        func scene(_ scene: UIScene,
                   continue userActivity: NSUserActivity) {
            SwiftFlutterSharingIntentPlugin.handleSceneUserActivity(userActivity)
        }
    }

The existing AppDelegate callbacks are preserved for backwards
compatibility with pre-scene hosts.

## Fork base

Upstream: `bhagat-techind/flutter_sharing_intent`
Base commit: `aa1672f547d6579585fa27df0b28ffa2a2544aaa` (2025-12-03)

See `LICENSE.relocat` for fork provenance.
