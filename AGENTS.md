# Repository Guidelines

## Project Structure & Module Organization

- This repository is the Formbricks iOS SDK, a Swift package (`Package.swift`, iOS 16+) distributed through Swift Package Manager only.
- The published library is the `FormbricksSDK` product; its source lives in `Sources/FormbricksSDK`.
- The public entry point is `Sources/FormbricksSDK/Formbricks.swift`; configuration lives in `Config.swift` and `Helpers/ConfigBuilder.swift`.
- Feature code is grouped by role: `Manager/` (user, survey, Embedded Data and presentation state), `Networking/` (API client, services, update queue), `Model/` (Codable payloads), `WebView/` (the survey WebView) and `Helpers/`.
- Unit tests live in `Tests/FormbricksSDKTests`, with JSON fixtures in `Tests/FormbricksSDKTests/Mock`.
- `Playground/` is a small demo app that uses the SDK from this checkout; its Xcode project is generated from `Playground/project.yml` with XcodeGen.
- `e2e/` holds the E2E harness: `e2e/server` (a Formbricks server on Linux), `e2e/tunnel` (Cloudflare quick tunnel) and `e2e/ios` (the XCUITest golden journey).
- `api/FormbricksSDK.api` is the committed public API snapshot; `scripts/` holds the CI, release and harness scripts.
- Generated output such as `.build/` and `build/` should not be edited by hand.

## Build, Test, and Development Commands

Every CI check has a `make` target; run them from the repo root. You need Xcode 26.3 and SwiftLint 0.65.1.

- `make check` runs every check below.
- `make lint` runs SwiftLint in strict mode; warnings fail it.
- `make format-check` checks formatting with swift-format; `make format` fixes it.
- `make build` builds for the iOS Simulator with warnings as errors.
- `make test` runs the unit tests on an iPhone simulator with code coverage. Pin a simulator with `DESTINATION='platform=iOS Simulator,id=...'`.
- `make api-check` compares the public API with `api/FormbricksSDK.api`. After an intended API change, run `make api-dump` and commit the updated snapshot.
- `make package-check` resolves and builds the package from a scratch consumer app through SPM.
- `make script-tests` runs the tests for the CI, release and E2E harness shell scripts (needs `jq`).
- After editing `Playground/project.yml`, run `xcodegen generate --spec Playground/project.yml` and commit the project too.
- E2E (`.github/workflows/e2e.yml`): the XCUITest golden journey runs against a real Formbricks server reached over an https tunnel. Locally: `e2e/ios/run-journey.sh build`, then `E2E_APP_URL=https://... E2E_USER_ID=... E2E_FEEDBACK=... e2e/ios/run-journey.sh test`.
- Releasing is in `RELEASING.md`: publishing the GitHub release creates the tag, and the tag is the release.

## Coding Style & Naming Conventions

- swift-format (`.swift-format`) owns layout; SwiftLint (`.swiftlint.yml`) checks semantics only.
- CI runs every check in `.github/workflows/ci.yml` (lint, format, build, unit tests, API check, package check, SonarQube, dependency review, workflow lint, E2E); `PR Check Summary` is the one required check.
- `workflow-lint` runs actionlint and zizmor on the workflows and shellcheck on `scripts/` and `e2e/` shell scripts.
- Keep the public API deliberate: anything `public` lands in `api/FormbricksSDK.api` and is reviewed there.

## Testing Guidelines

- Unit tests use XCTest and live in `Tests/FormbricksSDKTests`, named after the area under test (for example `AppearanceTests.swift`).
- Add or update tests when changing SDK behavior; new JSON fixtures must be added to the test target's `resources` in `Package.swift`.
- Run `make test` before opening a PR.
- No explicit coverage threshold is configured; CI reports coverage to SonarQube, whose quality gate must pass.

## Commit & Pull Request Guidelines

- Commits and PR titles follow Conventional Commits, such as `fix: wait for pending user updates before evaluating targeting [ENG-1817]` and `chore: bump to 2.3.1`.
- The PR title check (`.github/workflows/pr-title.yml`) enforces it, because release notes are generated from PR titles.
- Keep commit subjects short, imperative, and prefixed with `fix:`, `feat:`, `chore:`, `ci:`, or similar.
- PRs start with a ticket line (`Fixes ENG-1234` / `Ref ENG-1234`) and explain the behavioral change.
- Include screenshots or short recordings for changes to how surveys render.

## Agent skills

### Issue tracker

Linear, Engineering team (`ENG`); skills use the Linear MCP tools. See `docs/agents/issue-tracker.md`.

### Triage labels

No triage labels: the five roles map onto Linear workflow states. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root and ADRs in `docs/adr/`. See `docs/agents/domain.md`.
