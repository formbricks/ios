# Local entry points for the CI checks. CI runs these same targets, so `make check` passing
# here means the same jobs pass there.

SCHEME := FormbricksSDK
DERIVED_DATA ?= .build/xcode
# Empty picks an iPhone simulator on the newest runtime the selected Xcode supports
# (scripts/simulator-destination.sh). Pin one with DESTINATION='platform=iOS Simulator,id=...'.
DESTINATION ?=
SWIFT_PATHS := Package.swift Sources Tests $(wildcard Playground)
API_SNAPSHOT := api/FormbricksSDK.api
PRODUCTS := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator
SYMBOL_GRAPHS := $(DERIVED_DATA)/symbol-graphs
TEST_RESULTS := $(DERIVED_DATA)/TestResults.xcresult

.PHONY: check lint format format-check build test symbol-graphs api-dump api-check package-check script-tests

check: lint format-check build test api-check package-check script-tests

lint:
	swiftlint lint --strict

format:
	xcrun swift-format format --in-place --recursive --parallel $(SWIFT_PATHS)

format-check:
	xcrun swift-format lint --strict --recursive --parallel $(SWIFT_PATHS)

build:
	xcodebuild build \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED_DATA) \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

test:
	rm -rf "$(TEST_RESULTS)"
	destination='$(DESTINATION)'; \
	if [ -z "$$destination" ]; then destination="$$(scripts/simulator-destination.sh)" || exit 1; fi; \
	echo "Testing on $$destination"; \
	xcodebuild test \
		-scheme $(SCHEME) \
		-destination "$$destination" \
		-derivedDataPath $(DERIVED_DATA) \
		-resultBundlePath $(TEST_RESULTS) \
		-enableCodeCoverage YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

# The public API, read from the built module. The deployment target matches Package.swift.
symbol-graphs: build
	rm -rf "$(SYMBOL_GRAPHS)"
	mkdir -p $(SYMBOL_GRAPHS)
	xcrun swift-symbolgraph-extract \
		-module-name $(SCHEME) \
		-target arm64-apple-ios16.0-simulator \
		-sdk "$$(xcrun --sdk iphonesimulator --show-sdk-path)" \
		-I $(PRODUCTS) \
		-minimum-access-level public \
		-skip-inherited-docs \
		-output-dir $(SYMBOL_GRAPHS)

# After an intended public API change: regenerate the snapshot and commit it with the change.
api-dump: symbol-graphs
	scripts/api-snapshot.sh $(SYMBOL_GRAPHS) > $(API_SNAPSHOT)

api-check: symbol-graphs
	@scripts/api-snapshot.sh $(SYMBOL_GRAPHS) | diff -u $(API_SNAPSHOT) - \
		|| { echo "::error::The public API changed. If that is intended, run 'make api-dump' and commit $(API_SNAPSHOT)."; exit 1; }

package-check:
	scripts/package-check.sh

# Tests for the shell scripts the checks, the release workflow and the E2E harness run.
script-tests:
	scripts/tests/api-snapshot-test.sh
	scripts/tests/pr-check-summary-test.sh
	scripts/tests/simulator-destination-test.sh
	bash scripts/release/test-validate-tag.sh
	bash scripts/release/test-verify-spm-release.sh
	set -e; for test in e2e/*/test/*.sh; do echo "$$test"; "$$test"; done
