import XCTest
import SwiftUI
@testable import BrewDock

/// Renders the panel's tabs and popovers with sample packages, for the
/// website and for checking the design. Skipped unless SCREENSHOTS names an
/// output folder: `make screenshots`.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var out: URL!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOTS"], !dir.isEmpty else {
            throw XCTSkip("Set SCREENSHOTS to render screenshots")
        }
        out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    private func cask(_ name: String, _ version: String, app: String, outdated: Bool = false, held: Bool = false) -> BrewPackage {
        var package = BrewPackage(name: name, version: version, type: .cask, isOutdated: outdated, isHeld: held)
        let path = "/Applications/\(app).app"
        if FileManager.default.fileExists(atPath: path) {
            package.resolvedAppPath = path
            package.appIcon = NSWorkspace.shared.icon(forFile: path)
        }
        return package
    }

    private func sampleService() -> BrewService {
        let service = BrewService()
        service.casks = [
            cask("blender", "4.5.3", app: "Blender", outdated: true),
            cask("brewdock", "1.4.2", app: "BrewDock"),
            cask("karabiner-elements", "15.5.0", app: "Karabiner-Elements"),
            cask("steam", "4.0", app: "Steam", held: true),
            cask("transmission", "4.0.6", app: "Transmission", outdated: true),
        ]
        service.formulae = [
            BrewPackage(name: "ffmpeg", version: "7.1", type: .formula, isOutdated: true),
            BrewPackage(name: "gh", version: "2.62.0", type: .formula),
            BrewPackage(name: "node", version: "23.3.0", type: .formula),
            BrewPackage(name: "python@3.13", version: "3.13.1", type: .formula),
            BrewPackage(name: "wget", version: "1.25.0", type: .formula),
            BrewPackage(name: "openssl@3", version: "3.4.0", type: .formula, isDependency: true),
        ]
        service.services = [
            HomebrewService(name: "postgresql@18", status: .started, user: "ross"),
            HomebrewService(name: "redis", status: .started, user: "ross"),
            HomebrewService(name: "nginx", status: .stopped, user: ""),
            HomebrewService(name: "mysql", status: .error, user: "ross"),
        ]
        return service
    }

    func testRenderPanel() throws {
        // The website's shots are a little taller than the panel opens at
        let size = NSSize(width: AppDelegate.panelDefaultSize.width, height: 560)
        for dark in [false, true] {
            let service = sampleService()
            try Snapshot.panel(dark: dark, size: size, to: out.appendingPathComponent(dark ? "panel-dark.png" : "panel-apps.png")) {
                MenuBarView().environmentObject(service)
            }
        }
        for (tab, name) in [(MenuBarView.Tab.tools, "panel-tools"), (.services, "panel-services"),
                            (.discover, "panel-discover")] {
            let service = sampleService()
            try Snapshot.panel(size: size, to: out.appendingPathComponent("\(name).png")) {
                MenuBarView(initialTab: tab).environmentObject(service)
            }
        }
    }

    func testRenderPopovers() throws {
        let service = sampleService()
        for dark in [false, true] {
            try Snapshot.panel(dark: dark, to: out.appendingPathComponent("panel-settings\(dark ? "-dark" : "").png")) {
                SettingsView().environmentObject(service)
            }
        }
        try Snapshot.panel(to: out.appendingPathComponent("panel-about.png")) {
            AboutPopover(app: .brewDock) { Mascot(size: 56) }
        }
        try Snapshot.panel(to: out.appendingPathComponent("panel-brewfile.png")) {
            BrewfileView().environmentObject(service)
        }
    }
}
