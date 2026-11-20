# Formbricks iOS SDK

The iOS SDK for Formbricks

## Installation

### Swift Package Manager

1. In Xcode choose **File → Add Packages…**
2. Enter `https://github.com/formbricks/ios.git`.
3. Choose version rule (e.g. "Up to Next Major" starting at `2.3.1`).
4. Add the **FormbricksSDK** library product to your app target.
5. Import in your code:
   ```swift
   import FormbricksSDK
   ```

### Migrating from CocoaPods

New FormbricksSDK releases are distributed through Swift Package Manager only.
[CocoaPods Trunk is becoming read-only](https://blog.cocoapods.org/CocoaPods-Specs-Repo/),
with a test period on November 1–7, 2026 and a permanent switch on December 2, 2026.
Previously published pod versions remain available; migrate to receive future SDK updates.

1. Remove the `pod 'FormbricksSDK', ...` entry from every target in your `Podfile`.
2. Run `pod install` to update the workspace and lockfile. Keep any other pods your app uses.
3. Follow the Swift Package Manager instructions above and add **FormbricksSDK** to each app target that uses it.
   Do not link both the pod and the Swift package in the same target.
4. Keep `import FormbricksSDK` and your existing SDK calls. Build and test your app after switching.
   If you also upgrade the SDK version, review its [release notes](https://github.com/formbricks/ios/releases).

### Quickstart

```swift
import FormbricksSDK

// 1. Build your config (you can also inject userId + attributes here)
let config = FormbricksConfig.Builder(
        appUrl: "https://your‑app.bricks.com",
        workspaceId: "YOUR_WORKSPACE_ID"
    )
    .setLogLevel(.debug)
    .build()

// Note: `environmentId` is still supported as a deprecated alias for
// `workspaceId` and will be removed in a future release.
// Existing integrations using `environmentId` continue to work:
//
//   FormbricksConfig.Builder(
//       appUrl: "https://your‑app.bricks.com",
//       environmentId: "YOUR_ENV_ID" // deprecated, use workspaceId
//   )

// 2. Initialize the SDK (once per launch)
Formbricks.setup(with: config)

// 3. Identify the user
Formbricks.setUserId("user‑123")

// 4. Track events
Formbricks.track("button_pressed")

// 5. Set or add user attributes
Formbricks.setAttribute("blue", forKey: "favoriteColor")
Formbricks.setAttributes([
    "plan": "pro",
    "tier": "gold"
])

// 6. Change language (no userId required):
Formbricks.setLanguage("de")

// 7. Log out (no userId required):
Formbricks.logout()

// 8. Clean up SDK state (optional):
Formbricks.cleanup(waitForOperations: true) {
    print("SDK torn down")
}
```

### Dark mode

Surveys render light by default. Call `setAppearance` to change it:

```swift
Formbricks.setAppearance(.dark) // .light, .dark or .system
```

- Works before or after `setup`, or pass it in the config with `.set(appearance: .dark)`. Objective-C: `[Formbricks setAppearance:@"dark"]`.
- An open survey switches in place; the typed answer and current question stay.
- `.system` follows **your app's** theme (including `overrideUserInterfaceStyle`), not the phone's, and updates live.
- Kept across `logout()`, forgotten on app restart, never sent to the server. An unknown value is logged and falls back to light.
- Needs a Formbricks server that supports dark mode; an older server keeps surveys light.

Custom CSS configured in Formbricks needs no SDK call; it arrives with the workspace state.

## Development

Every CI check has a `make` target, so `make check` runs them all locally. You need Xcode 26.3 and
[SwiftLint](https://github.com/realm/SwiftLint) 0.65.1.

| Target | What it checks |
| --- | --- |
| `make lint` | SwiftLint, strict |
| `make format-check` | swift-format; `make format` fixes it |
| `make build` | builds with warnings as errors |
| `make test` | unit tests on an iPhone simulator |
| `make api-check` | the public API against `api/FormbricksSDK.api` |
| `make package-check` | an app can resolve and build the package through SPM |
| `make script-tests` | the CI, release and E2E harness shell scripts (needs `jq`) |

If you change the public API on purpose, run `make api-dump` and commit `api/FormbricksSDK.api` with the change.

### Playground and E2E

`Playground/Playground.xcodeproj` is a small app that uses the SDK from this checkout, with a button per
SDK call (set up, set user ID, set attribute, track, log out). Its source is `Playground/project.yml`; after
editing it, run `xcodegen generate --spec Playground/project.yml` and commit the project too.

The E2E workflow (`.github/workflows/e2e.yml`) runs its XCUITest golden journey against a real Formbricks
server. The server runs on Linux (`e2e/server/`) and the macOS job reaches it through a Cloudflare quick
tunnel (`e2e/tunnel/`), because the SDK only accepts `https://` app URLs. To run it locally against a
server you can reach over https:

```sh
e2e/ios/run-journey.sh build
E2E_APP_URL=https://... E2E_USER_ID=qa-user-local E2E_FEEDBACK="Local feedback" e2e/ios/run-journey.sh test
```

## Releasing

See [RELEASING.md](RELEASING.md). The tag is the release, so the manual E2E QA run must pass before you
publish.

<!-- CI demo PR, do not merge -->
