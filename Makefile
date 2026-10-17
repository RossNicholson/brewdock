.PHONY: release build test check-catalog screenshots discover-icons

# Ship a release: bump version, commit, tag, push -> CI builds/notarizes/publishes.
#   make release VERSION=1.2.3
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@scripts/cut-release.sh $(VERSION)

# Build a local notarized test DMG (does not publish).
build:
	@scripts/release.sh

# Run the unit tests.
test:
	@xcodegen generate >/dev/null && xcodebuild test -project BrewDock.xcodeproj \
		-scheme BrewDock -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet

# Check the Discover catalog against Homebrew (renamed/removed/disabled packages).
check-catalog:
	@scripts/check-catalog.sh

# Renders the panel and popovers with sample packages into build/screenshots,
# for the website and for checking the design
screenshots:
	xcodegen generate
	SCREENSHOTS="$(CURDIR)/build/screenshots" TEST_RUNNER_SCREENSHOTS="$(CURDIR)/build/screenshots" \
		xcodebuild test -project BrewDock.xcodeproj -scheme BrewDock -destination 'platform=macOS' \
		CODE_SIGNING_ALLOWED=NO -only-testing:BrewDockTests/ScreenshotTests -quiet
	@echo "Screenshots in build/screenshots"

# Downloads the Discover catalog's icons into BrewDock/DiscoverIcons (only the
# missing ones; ALL=1 fetches every icon again). Run after adding to the catalog.
discover-icons:
	swift scripts/fetch-discover-icons.swift $(if $(ALL),--all,)
