import XCTest
@testable import BrewDock

/// "Remember my apps": reading brew's installed list and working out what the
/// other Macs have that this one doesn't
final class MacLibraryTests: XCTestCase {

    private let installedJSON = """
    {
      "formulae": [
        {"name": "wget", "full_name": "wget", "desc": "Internet file retriever",
         "installed": [{"installed_on_request": true}]},
        {"name": "openssl@3", "full_name": "openssl@3", "desc": "Cryptography toolkit",
         "installed": [{"installed_on_request": false}]},
        {"name": "foo", "full_name": "someone/tap/foo", "desc": "",
         "installed": [{"installed_on_request": true}]}
      ],
      "casks": [
        {"token": "firefox", "full_token": "firefox", "name": ["Firefox"], "desc": "Web browser"},
        {"token": "brewdock", "full_token": "rossnicholson/tap/brewdock", "name": ["BrewDock"], "desc": ""},
        {"token": "clawdbar", "full_token": "rossnicholson/tap/clawdbar", "name": ["ClawdBar"], "desc": null}
      ]
    }
    """

    func testEntriesKeepRequestedFormulaeAndCasksButNotBrewDock() {
        let entries = MacLibrary.entries(fromInstalledJSON: installedJSON) ?? []
        XCTAssertEqual(entries.map(\.token), ["rossnicholson/tap/clawdbar", "firefox", "someone/tap/foo", "wget"])
        XCTAssertEqual(entries.first { $0.token == "firefox" }?.name, "Firefox")
        XCTAssertEqual(entries.first { $0.token == "rossnicholson/tap/clawdbar" }?.shortName, "clawdbar")
        XCTAssertEqual(entries.first { $0.token == "wget" }?.isCask, false)
    }

    func testEntriesIsNilForUnreadableOutput() {
        XCTAssertNil(MacLibrary.entries(fromInstalledJSON: ""))
        XCTAssertNil(MacLibrary.entries(fromInstalledJSON: "Error: something went wrong"))
    }

    private func entry(_ token: String, cask: Bool = true) -> MacSnapshot.Entry {
        .init(token: token, name: token, desc: "", isCask: cask)
    }

    func testMissingSkipsInstalledAndDismissedAndListsEachPackageOnce() {
        let older = MacSnapshot(macName: "Old iMac", updated: Date(timeIntervalSinceNow: -86_400),
                                packages: [entry("firefox"), entry("zed"), entry("wget", cask: false)])
        let newer = MacSnapshot(macName: "MacBook Air", updated: Date(),
                                packages: [entry("firefox"), entry("rossnicholson/tap/clawdbar"), entry("slack")])
        let groups = MacLibrary.missing(from: [older, newer], installedCasks: ["clawdbar"],
                                        installedFormulae: [], dismissed: ["slack"])
        XCTAssertEqual(groups.map(\.macName), ["MacBook Air", "Old iMac"])
        XCTAssertEqual(groups[0].packages.map(\.token), ["firefox"])
        XCTAssertEqual(groups[1].packages.map(\.token), ["zed", "wget"])
    }

    func testMissingDropsMacsWithNothingNew() {
        let mac = MacSnapshot(macName: "Mac mini", updated: Date(), packages: [entry("firefox")])
        XCTAssertTrue(MacLibrary.missing(from: [mac], installedCasks: ["firefox"],
                                         installedFormulae: [], dismissed: []).isEmpty)
    }

    func testFormulaWithSameNameAsCaskDoesNotCountAsInstalled() {
        let mac = MacSnapshot(macName: "Mac mini", updated: Date(), packages: [entry("docker", cask: false)])
        let groups = MacLibrary.missing(from: [mac], installedCasks: ["docker"], installedFormulae: [], dismissed: [])
        XCTAssertEqual(groups.first?.packages.map(\.token), ["docker"])
    }

    func testCatalogPackagesKeepTheirCatalogEntry() {
        let package = DiscoverPackage(otherMac: entry("rossnicholson/tap/clawdbar"))
        XCTAssertEqual(package.id, "clawdbar")
        XCTAssertTrue(package.isOwnApp)
        let unknown = DiscoverPackage(otherMac: entry("someone/tap/thing"))
        XCTAssertEqual(unknown.installToken, "someone/tap/thing")
    }
}
