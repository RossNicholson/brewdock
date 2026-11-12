import AppKit
import XCTest
@testable import BrewDock

/// Tests for the brittle bits: parsing Homebrew's command output. These are the
/// most likely things to silently break when Homebrew changes its formatting.
final class BrewParseTests: XCTestCase {

    // MARK: App Management

    func testSpotsTheAppManagementWarning() {
        let stderr = """
        Warning: Your terminal does not have App Management permissions, so Homebrew will delete and reinstall the app.
        This may result in some configurations (like notification settings or location in the Dock/Launchpad) being lost.
        """
        XCTAssertTrue(BrewParse.lacksAppManagement(stderr))
        XCTAssertFalse(BrewParse.lacksAppManagement("==> Upgrading keybar\n==> Moving App 'KeyBar.app' to '/Applications/KeyBar.app'"))
    }

    /// The installed Homebrew still prints that warning, and still behind the
    /// variable BrewDock sets
    func testInstalledHomebrewStillSaysIt() throws {
        let file = "/opt/homebrew/Library/Homebrew/cask/quarantine.rb"
        let source = try XCTUnwrap(try? String(contentsOfFile: file, encoding: .utf8), "no Homebrew at /opt/homebrew")
        XCTAssertTrue(source.contains("HOMEBREW_NO_APP_MANAGEMENT_PERMISSIONS_PROMPT"))
        XCTAssertTrue(BrewParse.lacksAppManagement(source))
    }

    // MARK: brew outdated --json=v2

    func testOutdatedJSONUsesShortNames() throws {
        let json = """
        {
          "formulae": [
            {"name": "mongodb/brew/mongodb-community", "installed_versions": ["8.0.1"], "current_version": "8.0.4", "pinned": false, "pinned_version": null},
            {"name": "python@3.13", "installed_versions": ["3.13.1"], "current_version": "3.13.2", "pinned": false, "pinned_version": null}
          ],
          "casks": [
            {"name": "ollama", "installed_versions": ["0.5.1"], "current_version": "0.5.4", "pinned": false, "pinned_version": null}
          ]
        }
        """
        let outdated = try XCTUnwrap(BrewParse.outdated(fromJSON: json))
        XCTAssertEqual(outdated.formulae, ["mongodb-community", "python@3.13"], "names as brew list prints them")
        XCTAssertEqual(outdated.casks, ["ollama"], "kept apart from formulae")
        // Matched by type: the ollama formula isn't outdated just because the cask is
        let formulae = BrewParse.packages(from: "ollama 0.5.4\nmongodb-community 8.0.1", type: .formula, outdated: outdated.formulae)
        XCTAssertEqual(formulae.map(\.isOutdated), [false, true])
    }

    func testOutdatedJSONEmptyAndFailed() {
        XCTAssertEqual(BrewParse.outdated(fromJSON: "{\n  \"formulae\": [],\n  \"casks\": []\n}")?.formulae, [])
        XCTAssertNil(BrewParse.outdated(fromJSON: ""), "a failed run isn't 'nothing outdated'")
        XCTAssertNil(BrewParse.outdated(fromJSON: "Error: Refusing to load cask"))
    }

    /// The installed Homebrew still names formulae by full name in the JSON
    func testInstalledHomebrewOutdatedJSON() throws {
        let file = "/opt/homebrew/Library/Homebrew/cmd/outdated.rb"
        let source = try XCTUnwrap(try? String(contentsOfFile: file, encoding: .utf8), "no Homebrew at /opt/homebrew")
        XCTAssertTrue(source.contains("f.full_name"))
        XCTAssertTrue(source.contains("formulae: json_info(formulae)"))
    }

    // MARK: brew bundle check

    func testBundleCheckMissing() {
        let stderr = """
        brew bundle can't satisfy your Brewfile's dependencies.
        → Cask zed needs to be installed or updated.
        → Formula cowsay needs to be installed or updated.
        → Tap user/tools needs to be tapped.
        → Service postgresql@16 needs to be started.
        Satisfy missing dependencies with `brew bundle install`.
        """
        XCTAssertEqual(BrewParse.bundleCheckMissing(fromStderr: stderr), ["zed", "cowsay", "user/tools", "postgresql@16"])
        XCTAssertEqual(BrewParse.bundleCheckMissing(fromStderr: "Error: Invalid Brewfile: syntax error found"), [])
    }

    func testInstalledHomebrewBundleCheckWording() throws {
        let file = "/opt/homebrew/Library/Homebrew/cmd/bundle/subcommand/check.rb"
        let alt = "/opt/homebrew/Library/Homebrew/bundle/subcommand/check.rb"
        let source = try XCTUnwrap((try? String(contentsOfFile: file, encoding: .utf8)) ?? (try? String(contentsOfFile: alt, encoding: .utf8)),
                                   "no Homebrew at /opt/homebrew")
        XCTAssertTrue(source.contains(#"$stderr.puts "→ #{error}""#))
    }

    // MARK: brew list --versions

    func testPackagesParsesNameAndVersion() {
        let out = """
        wget 1.21.4
        git 2.44.0
        """
        let pkgs = BrewParse.packages(from: out, type: .formula, outdated: [])
        XCTAssertEqual(pkgs.count, 2)
        XCTAssertEqual(pkgs[0].name, "wget")
        XCTAssertEqual(pkgs[0].version, "1.21.4")
        XCTAssertEqual(pkgs[0].type, .formula)
    }

    func testPackagesKeepsMultipleVersionsAsVersionString() {
        let pkgs = BrewParse.packages(from: "python@3.12 3.12.1 3.12.2", type: .formula, outdated: [])
        XCTAssertEqual(pkgs.first?.name, "python@3.12")
        XCTAssertEqual(pkgs.first?.version, "3.12.1 3.12.2")
    }

    func testPackagesFlagsOutdated() {
        let pkgs = BrewParse.packages(from: "wget 1.0\ngit 2.0", type: .formula, outdated: ["git"])
        XCTAssertFalse(pkgs[0].isOutdated)   // wget
        XCTAssertTrue(pkgs[1].isOutdated)    // git
    }

    func testPackagesHandlesNameWithoutVersion() {
        let pkgs = BrewParse.packages(from: "somecask", type: .cask, outdated: [])
        XCTAssertEqual(pkgs.first?.name, "somecask")
        XCTAssertEqual(pkgs.first?.version, "")
    }

    func testPackagesIgnoresBlankLines() {
        XCTAssertTrue(BrewParse.packages(from: "\n\n   \n", type: .formula, outdated: []).isEmpty)
    }

    // MARK: brew services list --json

    func testServicesParsesJSON() {
        let json = """
        [
          {"name":"redis","status":"started","user":"ross","file":"/x"},
          {"name":"postgresql","status":"stopped","user":null,"file":"/y"}
        ]
        """
        let svcs = BrewParse.services(fromJSON: json)
        XCTAssertEqual(svcs.count, 2)
        XCTAssertEqual(svcs[0].name, "redis")
        XCTAssertEqual(svcs[0].status, .started)
        XCTAssertEqual(svcs[0].user, "ross")
        XCTAssertEqual(svcs[1].status, .stopped)
        XCTAssertEqual(svcs[1].user, "")   // null user -> empty string
    }

    func testServicesUnknownStatusFallsBack() {
        let svcs = BrewParse.services(fromJSON: #"[{"name":"x","status":"weird","user":null}]"#)
        XCTAssertEqual(svcs.first?.status, .unknown)
    }

    func testServicesEmptyOrInvalidJSON() {
        XCTAssertTrue(BrewParse.services(fromJSON: "[]").isEmpty)
        XCTAssertTrue(BrewParse.services(fromJSON: "not json").isEmpty)
    }

    // MARK: brew info --json=v2 --cask

    func testCaskAppNamesExtractsAppArtifact() {
        let json = """
        {"casks":[
          {"token":"iterm2","artifacts":[{"app":["iTerm.app"]},{"zap":[{}]}]},
          {"token":"clionly","artifacts":[{"binary":["foo"]}]}
        ]}
        """
        let map = BrewParse.caskAppNames(fromJSON: json)
        XCTAssertEqual(map["iterm2"], ["iTerm.app"])
        XCTAssertEqual(map["clionly"], [])   // answered, but no app artifact
        XCTAssertNil(map["not-asked"])
    }

    func testCaskAppNamesPrefersTarget() {
        let json = #"{"casks":[{"token":"x","artifacts":[{"app":["Foo.app",{"target":"Bar.app"}]}]}]}"#
        XCTAssertEqual(BrewParse.caskAppNames(fromJSON: json)["x"], ["Bar.app"])
    }

    func testCaskAppNamesEmptyOnGarbage() {
        XCTAssertTrue(BrewParse.caskAppNames(fromJSON: "nope").isEmpty)
        XCTAssertTrue(BrewParse.caskAppNames(fromJSON: "{}").isEmpty)
    }

    // MARK: Discover catalog

    func testCatalogTokensAreUnique() {
        let ids = DiscoverCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate catalog tokens")
    }

    func testCatalogMatchesVersionedInstalls() {
        let python = DiscoverCatalog.all.first { $0.id == "python" }!
        XCTAssertTrue(python.matches(installedName: "python@3.15"))
        XCTAssertTrue(python.matches(installedName: "python"))
        XCTAssertFalse(python.matches(installedName: "python-setuptools"))
    }

    func testTapPackagesInstallByQualifiedName() {
        let clawdbar = DiscoverCatalog.all.first { $0.id == "clawdbar" }!
        XCTAssertEqual(clawdbar.installToken, "rossnicholson/tap/clawdbar")
        XCTAssertTrue(clawdbar.matches(installedName: "clawdbar"))
        let keybar = DiscoverCatalog.all.first { $0.id == "keybar" }!
        XCTAssertEqual(keybar.installToken, "rossnicholson/tap/keybar")
        XCTAssertNotNil(keybar.bundledIcon)
        let reporadar = DiscoverCatalog.all.first { $0.id == "reporadar" }!
        XCTAssertEqual(reporadar.installToken, "rossnicholson/tap/reporadar")
        XCTAssertNotNil(reporadar.bundledIcon)
        let macping = DiscoverCatalog.all.first { $0.id == "macping" }!
        XCTAssertEqual(macping.installToken, "rossnicholson/tap/macping")
        XCTAssertNotNil(macping.bundledIcon)
        XCTAssertEqual(DiscoverCatalog.all.first { $0.id == "git" }?.installToken, "git")
    }

    // MARK: brew error output

    func testErrorSummaryPrefersErrorLine() {
        let stderr = """
        Warning: No available formula with the name "nope".
        Error: No formulae found for nope.
        ==> Searching for similarly named formulae...
        """
        XCTAssertEqual(BrewParse.errorSummary(fromStderr: stderr), "No formulae found for nope")
    }

    func testErrorSummaryFallsBackToWarningThenLastLine() {
        XCTAssertEqual(BrewParse.errorSummary(fromStderr: "Warning: disk nearly full\n"), "disk nearly full")
        XCTAssertEqual(BrewParse.errorSummary(fromStderr: "curl: (6) Could not resolve host\n==> Retrying"), "curl: (6) Could not resolve host")
        XCTAssertNil(BrewParse.errorSummary(fromStderr: "  \n"))
    }

    // MARK: Update notifications

    func testUpdateNotificationMessage() {
        let one = UpdateNotifier.message(fresh: ["git"], total: 1)
        XCTAssertEqual(one.title, "1 Homebrew update ready")
        XCTAssertEqual(one.body, "New: git")
        let many = UpdateNotifier.message(fresh: ["a", "b", "c", "d", "e"], total: 7)
        XCTAssertEqual(many.title, "7 Homebrew updates ready")
        XCTAssertEqual(many.body, "New: a, b, c and 2 more")
    }

    func testAutoUpdatedMessage() {
        let one = UpdateNotifier.autoUpdatedMessage(["git"])
        XCTAssertEqual(one.title, "Updated 1 Homebrew package")
        XCTAssertEqual(one.body, "git")
        let many = UpdateNotifier.autoUpdatedMessage(["a", "b", "c", "d"])
        XCTAssertEqual(many.title, "Updated 4 Homebrew packages")
        XCTAssertEqual(many.body, "a, b, c and 1 more")
    }

    // MARK: Install progress

    func testProgressLabels() {
        let cases: [(String, String?)] = [
            ("==> Downloading https://ghcr.io/v2/homebrew/core/jq/blobs/sha256:abc", "Downloading…"),
            ("==> Fetching downloads for: jq", "Downloading…"),
            ("==> Fetching jq from homebrew/core", "Fetching jq…"),
            ("✔︎ Bottle jq (1.7.1)", "Downloaded jq"),
            ("✔︎ Bottle Manifest jq (1.7.1)", nil),
            ("Uninstalling /opt/homebrew/Cellar/cowsay/3.04_1... (64 files, 107KB)", "Uninstalling…"),
            ("==> Pouring jq--1.7.1.arm64_sequoia.bottle.tar.gz", "Unpacking…"),
            ("==> Installing Cask firefox", "Installing firefox…"),
            ("==> Upgrading 2 outdated packages:", nil),
            ("==> Upgrading node", "Upgrading node…"),
            ("==> Moving App 'Firefox.app' to '/Applications/Firefox.app'", "Moving to Applications…"),
            ("==> Running `brew cleanup jq`...", "Cleaning up…"),
            ("🍺  /opt/homebrew/Cellar/jq/1.7.1: 19 files, 1.2MB", nil),
            ("Already up-to-date.", nil),
        ]
        for (line, expected) in cases {
            XCTAssertEqual(BrewParse.progressLabel(fromLine: line), expected, line)
        }
    }

    // MARK: brew cleanup

    func testCleanupSize() {
        let dry = """
        Would remove: /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.6 (1,707 files, 34.6MB)
        ==> This operation would free approximately 644.8MB of disk space.
        """
        XCTAssertEqual(BrewParse.cleanupSize(fromOutput: dry), "644.8 MB")
        XCTAssertEqual(BrewParse.cleanupSize(fromOutput: "==> This operation has freed approximately 1.2GB of disk space."), "1.2 GB")
        XCTAssertNil(BrewParse.cleanupSize(fromOutput: ""))
    }

    // MARK: brew search

    func testSearchNamesSkipsHeadingsAndMessages() {
        let out = "==> Formulae\nmarkdown\nhtml2markdown\n\nNo casks found for \"x\".\n"
        XCTAssertEqual(BrewParse.searchNames(fromOutput: out), ["markdown", "html2markdown"])
    }

    func testPackageSummaries() {
        let json = """
        {"formulae":[{"name":"jq","full_name":"jq","desc":"JSON processor"}],
         "casks":[{"token":"macdown","full_token":"macdown","name":["MacDown"],"desc":"Markdown editor"}]}
        """
        let s = BrewParse.packageSummaries(fromJSON: json)
        XCTAssertEqual(s.map(\.id), ["jq", "macdown"])
        XCTAssertEqual(s[1].name, "MacDown")
        XCTAssertEqual(s[1].type, .cask)
    }

    func testTapQualifiedResultMatchesShortInstalledName() {
        let pkg = DiscoverPackage(searchResult: "user/tap/foo", displayName: "foo", description: "", type: .formula)
        XCTAssertTrue(pkg.matches(installedName: "foo"))
    }

    // MARK: Untrusted taps (Homebrew 7)

    func testUntrustedTargets() {
        let stderr = """
        Error: Refusing to load cask rossnicholson/tap/brewdock from untrusted tap rossnicholson/tap.
        Run `brew trust --cask rossnicholson/tap/brewdock` or `brew trust rossnicholson/tap` to trust it.
        """
        let targets = BrewParse.untrustedTargets(fromStderr: stderr)
        XCTAssertEqual(targets, [UntrustedTarget(kind: .cask, name: "rossnicholson/tap/brewdock")])
        XCTAssertEqual(targets.first?.shortName, "brewdock")
        XCTAssertEqual(targets.first?.tap, "rossnicholson/tap")
        XCTAssertEqual(BrewParse.untrustedTargets(fromStderr: "Error: Refusing to load formula me/x/foo from untrusted tap me/x.").first?.kind, .formula)
        XCTAssertTrue(BrewParse.untrustedTargets(fromStderr: "Error: No formulae found").isEmpty)
    }

    func testCaskroomFallback() {
        let pkgs = BrewParse.caskroomPackages(["vlc": ["3.0.21", ".metadata"], "brewdock": ["1.2.0"]], outdated: ["vlc"])
        XCTAssertEqual(pkgs.map(\.name), ["brewdock", "vlc"])
        XCTAssertEqual(pkgs[1].version, "3.0.21")
        XCTAssertTrue(pkgs[1].isOutdated)
    }

    func testSelfDetectedByShortOrFullName() {
        XCTAssertTrue(BrewService.listsSelf("rossnicholson/tap/brewdock\n"))
        XCTAssertTrue(BrewService.listsSelf("brewdock"))
        XCTAssertFalse(BrewService.listsSelf("brewdockextra"))
    }

    // MARK: brew bundle cleanup

    func testCleanupCandidatesIgnoresHeadingsAndCachePaths() {
        let out = """
        Would uninstall formulae:
        cowsay
        Would uninstall casks:
        firefox vlc
        Would untap:
        someone/tap
        Would `brew cleanup`:
        Would remove: /Users/me/Library/Caches/Homebrew/bootsnap/abc (1,894 files, 16.9MB)
        Run `brew bundle cleanup --force` to make these changes.
        """
        XCTAssertEqual(BrewParse.cleanupCandidates(fromOutput: out),
                       ["cowsay", "firefox", "vlc", "someone/tap (tap)"])
        XCTAssertTrue(BrewParse.cleanupCandidates(fromOutput: "Would `brew cleanup`:\nWould remove: /x").isEmpty)
    }
}

/// Every Discover entry with an icon source ships its icon (make discover-icons)
final class DiscoverIconTests: XCTestCase {
    func testCatalogIconsShip() {
        let missing = DiscoverCatalog.all
            .filter { $0.iconURL != nil && $0.bundledIcon == nil }
            .filter { NSImage(named: "discover-\($0.id)") == nil }
            .map(\.id)
        XCTAssertEqual(missing, [], "Run make discover-icons")
    }
}
