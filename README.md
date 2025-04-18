# Formbricks iOS SDK

The iOS SDK for Formbricks

## Installation

### Swift Package Manager

1. In Xcode choose **File → Add Packages…**
2. Enter your repo URL (e.g. `https://github.com/formbricks/ios.git`)
3. Choose version rule (e.g. "Up to Next Major" starting at `1.0.0`).
4. Import in your code:
   ```swift
   import FormbricksSDK
   ```

### CocoaPods

1. Add the following to your `Podfile`:

   ```ruby
   platform :ios, '16.6'
   use_frameworks! :linkage => :static

   target 'YourTargetName' do
     pod 'FormbricksSDK', '1.0.0 (or the latest version)'
   end
   ```

2. Run `pod install` in your project directory
3. Import in your code:
   ```swift
   import FormbricksSDK
   ```

### Quickstart

```swift
import FormbricksSDK

// 1. Build your config (you can also inject userId + attributes here)
let config = FormbricksConfig.Builder(
        appUrl: "https://your‑app.bricks.com",
        environmentId: "YOUR_ENV_ID"
    )
    .setLogLevel(.debug)
    .build()

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

```

```
