# Releasing the iOS SDK

Swift Package Manager installs the SDK straight from a git tag in this repo. There is no registry
upload: **publishing the GitHub release creates the tag, and the tag is the release.** Consumers can
resolve it the moment it exists.

The shared SDK QA and release runbook lives in Notion: <!-- NOTION_SDK_QA_RELEASE_URL -->

## Accepted exception: QA must pass before you publish

The other SDKs build and publish inside their release workflow. iOS has nothing to gate, because the
tag goes public as soon as you publish the release, and tags are never deleted. So nothing automated
stops an untested release here.

**Run the manual QA first and only publish once it passes:**

1. In Actions, open the E2E workflow and choose **Run workflow** on `main`.
2. Set `server_version` to the Formbricks server image you are releasing against (for example
   `6.3.0-rc.1`), or leave it as `latest`.
3. Wait for the run to go green.

## Publish

1. Draft a new release in GitHub Releases on `main`.
2. Create the tag in the form `MAJOR.MINOR.PATCH`, for example `2.4.0`.
   - **No `v` prefix.** The release workflow fails on `v2.4.0`.
   - Prereleases are allowed and ship as SPM prerelease tags: `2.4.0-rc.1`. Tick
     **Set as a pre-release** for them. SPM only picks a prerelease when the consumer asks for it
     (for example `.package(url:exact: "2.4.0-rc.1")`).
3. Generate the release notes. They are built from the semantic PR titles and are the changelog.
4. Publish.

There is no version bump PR: `Package.swift` carries no version, the tag is the version.

## What the release workflow does

`.github/workflows/release.yml` runs on `release: published` and only verifies:

| Job            | Checks                                                                                                                              |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `validate-tag` | The tag is plain SemVer 2.0.0 (`scripts/release/validate-tag.sh`).                                                                  |
| `verify`       | `git ls-remote` sees the tag (polled for up to 10 minutes), then a scratch package resolves exactly that version through SwiftPM (`scripts/release/verify-spm-release.sh`). |

## When the run fails

- **`validate-tag` failed.** The badly named tag is already public. Do not delete it. Publish a new
  release with a correct tag (bump the patch version if needed) after QA.
- **`verify` failed.** Read the log. A timeout on `git ls-remote` is usually transient: use
  **Re-run failed jobs**, which is always safe. A SwiftPM resolution error means the tagged commit is
  not a valid package; fix it on `main` and publish a new patch release.

## Testing the scripts

```sh
bash scripts/release/test-validate-tag.sh
bash scripts/release/test-verify-spm-release.sh   # needs git and a Swift toolchain
```
