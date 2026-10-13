import XCTest
@testable import BrewDock

/// Tests for the brittle bits: parsing Homebrew's command output. These are the
/// most likely things to silently break when Homebrew changes its formatting.
final class BrewParseTests: XCTestCase {

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

    // MARK: Install progress

    func testProgressLabels() {
        let cases: [(String, String?)] = [
            ("==> Downloading https://ghcr.io/v2/homebrew/core/jq/blobs/sha256:abc", "Downloading…"),
            ("==> Fetching downloads for: jq", "Downloading…"),
            ("==> Fetching jq from homebrew/core", "Fetching jq…"),
            ("✔︎ Bottle jq (1.7.1)", "Downloaded jq"),
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
}
