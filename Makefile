.PHONY: release build test check-catalog

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
