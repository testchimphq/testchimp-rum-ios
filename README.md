# TestChimp RUM — iOS

Swift package for emitting structured RUM events to [TestChimp](https://testchimp.io), aligned with:

- [@testchimp/rum-js](https://www.npmjs.com/package/@testchimp/rum-js) (browser)
- [testchimp-rum-android](https://github.com/testchimphq/testchimp-rum-android) (Kotlin)

Same HTTP paths, headers (`Project-Id`, `TestChimp-Api-Key`, optional `ci-test-info`), validation rules, and Mobilewright automation URL contract.

> **Note:** [JitPack](https://jitpack.io/) is for JVM/Android. **iOS uses Swift Package Manager** with this **public Git URL + SemVer tags** — no Maven coordinates.

## Requirements

- **iOS 13+** (Swift 5.9+)
- **macOS 11+** target is included for SPM resolution; UI/session metadata uses UIKit on iOS.

## Add to your Xcode project

### Swift Package Manager (recommended)

1. In Xcode: **File → Add Package Dependencies…**
2. Enter **`https://github.com/testchimphq/testchimp-rum-ios.git`**
3. **Dependency Rule:** “Up to Next Major” on a published tag (e.g. `0.1.0`), or a branch during development.
4. Add the **TestChimpRum** product to your app target.

**Package.swift (for app packages / CI):**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [.iOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/testchimphq/testchimp-rum-ios.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [.product(name: "TestChimpRum", package: "testchimp-rum-ios")]
        ),
    ]
)
```

The **`package:`** name in `.product(...)` must match the **last path segment** of the Git URL (`testchimp-rum-ios`).

### Publishing this library (maintainers)

1. Tag releases SemVer-style: **`git tag 0.1.0 && git push origin 0.1.0`**, or run **`./scripts/release-spm-tag.sh 0.1.0`** (annotated tag + push).
2. Ensure `Package.swift` at the repo root defines the `TestChimpRum` library (this repo layout).
3. Consumers pin by tag or version range in SPM.

## Usage

```swift
import TestChimpRum

TestChimpRum.initialize(TestChimpRumConfig(
    projectId: "YOUR_PROJECT_ID",
    apiKey: "YOUR_API_KEY",
    environment: "staging"
))

TestChimpRum.emit(TestChimpEmitInput(title: "button_tap", metadata: ["screen": "Home"]))
```

Use `config: TestChimpRumConfig.Inner(...)` for advanced options (mirrors JS `config`: `captureEnabled`, `maxEventsPerSession`, `eventSendIntervalMillis`, `testchimpEndpoint`, `automationContextTtlSeconds`, etc.).

### TrueCoverage (Mobilewright)

1. **CI:** `export TESTCHIMP_PROJECT_TYPE=ios`. Use `@testchimp/playwright` with `installTestChimp` so hooks call `device.openUrl` automatically (see that package’s README).

2. **Register URL scheme** `testchimp-rum` in the app target (**Info → URL Types**), or use the associated domains flow if you standardize on universal links later.

3. **Forward URLs** to the SDK:

**UIKit `AppDelegate`:**

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return TestChimpRum.handleAutomationURL(url)
}
```

**SwiftUI:**

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = TestChimpRum.handleAutomationURL(url)
                }
        }
    }
}
```

**Default URLs** (overridable via `TESTCHIMP_RUM_AUTOMATION_SET_PREFIX` / `TESTCHIMP_RUM_AUTOMATION_CLEAR_URL` on the runner):

- Set: `testchimp-rum://truecoverage/v1/set?p=<base64url(JSON)>`
- Clear: `testchimp-rum://truecoverage/v1/clear`

## Building / sanity check (CLI)

```bash
swift build
# iOS slice (requires Xcode toolchain):
# xcodebuild -scheme TestChimpRum -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## License

MIT — see [LICENSE](LICENSE).
