import Foundation
import AppKit
import SwiftUI

struct BrewPackage: Identifiable {
    var id: String { "\(type):\(name)" }
    let name: String
    let version: String
    let type: PackageType
    var isOutdated: Bool = false
    var resolvedAppPath: String? = nil
    var appIcon: NSImage? = nil  // cached once during refresh — not recomputed on every redraw

    enum PackageType {
        case cask, formula
    }

    /// BrewDock's own cask. Brew can't upgrade or remove it from a child process,
    /// because the cask quits the app (and kills that child) partway through.
    var isBrewDock: Bool {
        type == .cask && name == BrewService.selfCaskName
    }

    var isCLIOnly: Bool {
        type == .cask && resolvedAppPath == nil
    }

    var appURL: URL? {
        resolvedAppPath.map { URL(fileURLWithPath: $0) }
    }

    var formulaIcon: FormulaIcon? {
        FormulaIcons.icon(for: name)
    }

    var runningApplication: NSRunningApplication? {
        guard type == .cask, let appPath = resolvedAppPath else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.path == appPath
        }
    }
}

// NSImage is not Hashable — provide manual conformance that ignores the icon
extension BrewPackage: Hashable {
    static func == (lhs: BrewPackage, rhs: BrewPackage) -> Bool {
        lhs.id == rhs.id && lhs.isOutdated == rhs.isOutdated
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HomebrewService: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let status: Status
    let user: String

    enum Status: String {
        case started, stopped, error, none = "none", unknown

        var color: Color {
            switch self {
            case .started: return .green
            case .error: return .red
            case .stopped, .none: return Color(nsColor: .secondaryLabelColor)
            case .unknown: return .orange
            }
        }

        var symbol: String {
            switch self {
            case .started: return "circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .stopped: return "circle"
            case .none: return "minus.circle"
            case .unknown: return "questionmark.circle"
            }
        }

        var displayLabel: String {
            self == .none ? "not started" : rawValue
        }
    }
}

@MainActor
class BrewService: ObservableObject {
    @Published var casks: [BrewPackage] = []
    @Published var formulae: [BrewPackage] = []
    @Published var services: [HomebrewService] = []
    @Published var isLoading = false
    @Published var isLoadingServices = false
    @Published var updatingPackages: Set<String> = []
    @Published var removingPackages: Set<String> = []
    @Published var installingPackages: Set<String> = []
    @Published var managingServices: Set<String> = []
    /// Latest progress label per package being installed/updated/removed, e.g.
    /// "Downloading…". `allUpdatesKey` holds "Update all" progress.
    @Published var progress: [String: String] = [:]
    nonisolated static let allUpdatesKey = "*all*"
    /// Settings toggle: also treat casks that update themselves (Chrome, Slack…)
    /// as outdated. Homebrew skips them by default.
    nonisolated static let includeAutoUpdatingKey = "includeAutoUpdatingApps"
    private var greedyFlags: [String] {
        UserDefaults.standard.bool(forKey: Self.includeAutoUpdatingKey) ? ["--greedy-auto-updates"] : []
    }
    @Published var lastError: String? = nil
    @Published var isBrewfileWorking = false
    @Published var selfUpdateAvailable: Bool = false
    @Published var isCheckingSelfUpdate: Bool = false
    @Published var isUpdatingSelf: Bool = false
    nonisolated static let selfCaskName = "brewdock"
    private var outdatedNames: Set<String> = []
    private var lastRefresh: Date = .distantPast
    /// A forced refresh requested while one was already running; it runs again
    /// afterwards so the list reflects changes made mid-refresh.
    private var refreshQueued = false
    /// Resolved cask token → app bundle path. `brew info` is slow over many casks,
    /// so we only query it for casks we haven't already resolved.
    private var appPathCache: [String: String] = [:]
    /// Casks `brew info` reported with no app bundle (CLI-only), so we don't ask again.
    private var appPathMisses: Set<String> = []
    private static let refreshTTL: TimeInterval = 30

    func refresh(force: Bool = false) async {
        if isLoading {
            if force { refreshQueued = true }
            return
        }
        // The panel triggers refresh on every open; skip if we refreshed recently
        // so reopening feels instant. The manual refresh button and every
        // install/update/uninstall pass force: true.
        if !force, Date().timeIntervalSince(lastRefresh) < Self.refreshTTL { return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            refreshQueued = false
            await loadPackages()
        } while refreshQueued
    }

    private func loadPackages() async {
        async let caskResult    = brew(["list", "--cask", "--versions"])
        async let formulaResult = brew(["list", "--formula", "--versions"])
        async let outdatedResult = brew(["outdated", "--quiet"] + greedyFlags)

        let (caskRes, formulaRes, outdatedRes) = await (caskResult, formulaResult, outdatedResult)

        outdatedNames = Set(outdatedRes.output.lines)
        var parsedCasks = BrewParse.packages(from: caskRes.output, type: .cask, outdated: outdatedNames)

        if !parsedCasks.isEmpty {
            await resolveAppPaths(forCaskNames: parsedCasks.map(\.name))
            parsedCasks = parsedCasks.map { pkg in
                var p = pkg
                if let path = appPathCache[pkg.name] {
                    p.resolvedAppPath = path
                    p.appIcon = NSWorkspace.shared.icon(forFile: path)
                }
                return p
            }
        }

        self.casks = parsedCasks
        self.formulae = BrewParse.packages(from: formulaRes.output, type: .formula, outdated: outdatedNames)
        lastRefresh = Date()
    }

    /// Populate `appPathCache` for any cask tokens we don't yet know, by asking
    /// `brew info` only about the unknown ones and resolving them against disk.
    private func resolveAppPaths(forCaskNames names: [String]) async {
        let unknown = names.filter { appPathCache[$0] == nil && !appPathMisses.contains($0) }
        guard !unknown.isEmpty else { return }
        let infoRes = await brew(["info", "--json=v2", "--cask"] + unknown, timeout: 120)
        let parsed = BrewParse.caskAppNames(fromJSON: infoRes.output)
        // A token missing from `parsed` means brew didn't answer (failed or timed
        // out), so it's retried next refresh. One brew answered for but with no
        // app on disk (CLI-only) is remembered as a miss.
        for (token, appNames) in parsed {
            let candidates = appNames.flatMap { name -> [String] in
                if name.hasPrefix("/") || name.hasPrefix("~") {
                    return [NSString(string: name).expandingTildeInPath]
                }
                return ["/Applications/\(name)",
                        NSString(string: "~/Applications/\(name)").expandingTildeInPath]
            }
            if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                appPathCache[token] = path
            } else {
                appPathMisses.insert(token)
            }
        }
    }

    /// Line handler that turns brew output into a progress label for `key`
    private func reportProgress(to key: String) -> @Sendable (String) -> Void {
        progress[key] = nil
        return { line in
            guard let label = BrewParse.progressLabel(fromLine: line) else { return }
            Task { @MainActor [weak self] in self?.progress[key] = label }
        }
    }

    func upgrade(_ package: BrewPackage) async {
        if package.isBrewDock { await updateSelf(); return }
        updatingPackages.insert(package.name)
        defer { updatingPackages.remove(package.name) }
        let flags = package.type == .cask ? ["--cask"] + greedyFlags : ["--formula"]
        let result = await brew(["upgrade"] + flags + [package.name], timeout: nil,
                                onLine: reportProgress(to: package.name))
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't update \(package.name)") }
        await refresh(force: true)
    }

    func install(_ package: DiscoverPackage) async {
        installingPackages.insert(package.id)
        defer { installingPackages.remove(package.id) }
        let flag = package.type == .cask ? "--cask" : "--formula"
        let result = await brew(["install", flag, package.installToken], timeout: nil,
                                onLine: reportProgress(to: package.id))
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't install \(package.displayName)") }
        await refresh(force: true)
    }

    func uninstall(_ package: BrewPackage) async {
        if package.isBrewDock {
            if !launchDetachedSelfBrew(.uninstall) { lastError = "Couldn't start the uninstaller." }
            return
        }
        removingPackages.insert(package.name)
        defer { removingPackages.remove(package.name) }
        let flag = package.type == .cask ? "--cask" : "--formula"
        let result = await brew(["uninstall", flag, package.name], timeout: nil,
                                onLine: reportProgress(to: package.name))
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't uninstall \(package.name)") }
        await refresh(force: true)
    }

    // Called on launch — quick check against local cache, no network fetch
    func checkSelfUpdateSilent() async {
        let result = await brew(["outdated", "--cask", "brewdock"])
        selfUpdateAvailable = result.output.lines.contains { $0.trimmingCharacters(in: .whitespaces) == "brewdock" }
    }

    // Called when the user explicitly clicks "Check for Updates" — runs brew update first.
    // `showProgress: false` lets the periodic background timer refresh quietly.
    func checkSelfUpdate(showProgress: Bool = true) async {
        if showProgress { isCheckingSelfUpdate = true }
        defer { if showProgress { isCheckingSelfUpdate = false } }
        _ = await brew(["update"], timeout: 60)
        let result = await brew(["outdated", "--cask", "brewdock"])
        selfUpdateAvailable = result.output.lines.contains { $0.trimmingCharacters(in: .whitespaces) == "brewdock" }
    }

    func updateSelf() async {
        isUpdatingSelf = true
        // An app can't replace itself from a `brew` subprocess it has to quit first:
        // the cask's `quit:` directive kills us, and the child brew dies mid-upgrade
        // (its stdout pipe breaks), leaving the app closed and un-updated. Hand the
        // work to a detached helper that outlives us, then quit so it can take over.
        guard launchDetachedSelfBrew(.upgrade) else {
            isUpdatingSelf = false
            lastError = "Couldn't start the updater."
            return
        }
    }

    private enum SelfBrewCommand: String {
        case upgrade, uninstall
    }

    /// Writes a script and launches it fully detached (its own null stdio,
    /// reparented to launchd) so it survives this process quitting, then quits.
    /// The script waits for us to exit, runs `brew <command> --cask brewdock`,
    /// and after an upgrade relaunches the freshly installed build.
    private func launchDetachedSelfBrew(_ command: SelfBrewCommand) -> Bool {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        let dir = support.appendingPathComponent("BrewDock", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent("self-\(command.rawValue).sh")
        // The log lives outside the BrewDock folder an uninstall `zap` would remove.
        let logURL = (command == .uninstall ? fm.temporaryDirectory : dir)
            .appendingPathComponent("brewdock-self-\(command.rawValue).log")

        let pid = ProcessInfo.processInfo.processIdentifier
        let appPath = Bundle.main.bundlePath
        let bundleID = Bundle.main.bundleIdentifier ?? "com.rossnicholson.BrewDock"
        let onSuccess = command == .upgrade ? "open -b \"\(bundleID)\" || open \"\(appPath)\"" : ":"

        // Note: `$(...)`, `$LOG`, `$status` are literal shell — only `\(...)` is
        // interpolated by Swift. Paths are quoted to tolerate spaces.
        let script = """
        #!/bin/sh
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        LOG="\(logURL.path)"
        : > "$LOG"
        echo "[$(date)] waiting for BrewDock (pid \(pid)) to quit" >> "$LOG"
        for i in $(seq 1 60); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.5
        done
        echo "[$(date)] running brew \(command.rawValue) --cask \(Self.selfCaskName)" >> "$LOG"
        "\(brewPath)" \(command.rawValue) --cask \(Self.selfCaskName) >> "$LOG" 2>&1
        status=$?
        echo "[$(date)] brew exited with status $status" >> "$LOG"
        if [ "$status" -eq 0 ]; then
            \(onSuccess)
        else
            osascript -e 'display notification "BrewDock \(command.rawValue) failed — see \(logURL.path)" with title "BrewDock"' >/dev/null 2>&1 || true
        fi
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        // Detached stdio: a broken pipe to this (dying) process must not abort the helper.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    func upgradeAll() async {
        // Bug fix: do NOT set isLoading = true here — refresh() owns that flag.
        // Setting it here caused refresh()'s guard to short-circuit, leaving the list stale.
        // Upgrade everything except BrewDock by name: a plain `brew upgrade` would
        // quit us mid-run. BrewDock goes last, through the detached updater.
        let outdatedCasks = casks.filter { $0.isOutdated && !$0.isBrewDock }.map(\.name)
        let outdatedFormulae = formulae.filter(\.isOutdated).map(\.name)
        let selfOutdated = casks.contains { $0.isOutdated && $0.isBrewDock }
        updatingPackages.formUnion(outdatedCasks + outdatedFormulae)
        var failure: BrewResult? = nil
        if !outdatedFormulae.isEmpty {
            let result = await brew(["upgrade", "--formula"] + outdatedFormulae, timeout: nil,
                                    onLine: reportProgress(to: Self.allUpdatesKey))
            if result.exitCode != 0 { failure = result }
        }
        if !outdatedCasks.isEmpty {
            let result = await brew(["upgrade", "--cask"] + greedyFlags + outdatedCasks, timeout: nil,
                                    onLine: reportProgress(to: Self.allUpdatesKey))
            if result.exitCode != 0 { failure = failure ?? result }
        }
        updatingPackages.subtract(outdatedCasks + outdatedFormulae)
        let failed = failure != nil
        if let failure { lastError = failure.failureMessage("Some updates failed") }
        if selfOutdated && !failed {
            await updateSelf()
            return
        }
        await refresh(force: true)
    }

    func brewfileDump(to path: String) async -> (success: Bool, message: String) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "dump", "--file=\(path)", "--force"])
        guard result.exitCode == 0 else { return (false, result.failureMessage("Couldn't export the Brewfile")) }
        return (true, "Brewfile saved.")
    }

    func brewfileInstall(from path: String) async -> (success: Bool, message: String) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "install", "--file=\(path)"], timeout: nil)
        await refresh(force: true)
        guard result.exitCode == 0 else { return (false, result.failureMessage("Some packages didn't install")) }
        return (true, "All packages installed.")
    }

    func brewfileCheck(at path: String) async -> (success: Bool, message: String) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "check", "--file=\(path)", "--verbose"], timeout: 120)
        if result.exitCode == 0 { return (true, "All packages are installed.") }
        let missing = result.output.lines.filter { $0.hasPrefix("x ") }.map { String($0.dropFirst(2)) }
        return (false, missing.isEmpty ? "Some packages are missing." : "Missing: \(missing.joined(separator: ", "))")
    }

    func brewfileCleanupPreview(at path: String) async -> [String] {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "cleanup", "--file=\(path)"])
        return result.output.lines.filter { !$0.isEmpty }
    }

    func brewfileCleanup(at path: String) async -> (success: Bool, message: String) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "cleanup", "--file=\(path)", "--force"], timeout: nil)
        await refresh(force: true)
        guard result.exitCode == 0 else { return (false, result.failureMessage("Cleanup failed")) }
        return (true, "Cleanup complete.")
    }

    /// How much `brew cleanup --prune=all` would free (old versions and every
    /// cached download), e.g. "644.8 MB", or nil if nothing.
    func measureCleanup() async -> String? {
        let result = await brew(["cleanup", "--dry-run", "--prune=all"], timeout: 120)
        return BrewParse.cleanupSize(fromOutput: result.output)
    }

    func cleanup() async -> (success: Bool, message: String) {
        let result = await brew(["cleanup", "--prune=all"], timeout: nil)
        guard result.exitCode == 0 else { return (false, result.failureMessage("Cleanup failed")) }
        return (true, BrewParse.cleanupSize(fromOutput: result.output).map { "Freed \($0)" } ?? "All tidy")
    }

    func refreshServices() async {
        guard !isLoadingServices else { return }
        isLoadingServices = true
        defer { isLoadingServices = false }
        let result = await brew(["services", "list", "--json"])
        services = BrewParse.services(fromJSON: result.output)
    }

    func startService(_ service: HomebrewService) async {
        await manageService(service, command: "start")
    }

    func stopService(_ service: HomebrewService) async {
        await manageService(service, command: "stop")
    }

    func restartService(_ service: HomebrewService) async {
        await manageService(service, command: "restart")
    }

    private func manageService(_ service: HomebrewService, command: String) async {
        managingServices.insert(service.name)
        defer { managingServices.remove(service.name) }
        let result = await brew(["services", command, service.name], timeout: 120)
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't \(command) \(service.name)") }
        await refreshServices()
    }

}

let brewPath: String = {
    let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/brew"
}()

private struct BrewResult {
    let output: String
    var errorOutput: String = ""
    let exitCode: Int32

    /// "Couldn't update git: <brew's error>", or just the first part when brew
    /// gave no reason
    func failureMessage(_ base: String) -> String {
        BrewParse.errorSummary(fromStderr: errorOutput).map { "\(base): \($0)" } ?? base
    }
}

/// Collects stderr on one thread while stdout is read on another.
private final class StderrBox: @unchecked Sendable {
    var data = Data()
}

/// Deterministic environment for every `brew` invocation. A Finder-launched app
/// inherits a minimal environment, so we set an explicit PATH (incl. the brew
/// prefix, for the git/curl/etc. brew shells out to), HOME, a UTF-8 locale, and
/// disable implicit auto-update + hint noise so output stays parseable.
private let brewEnvironment: [String: String] = {
    var env = ProcessInfo.processInfo.environment
    let prefix = (brewPath as NSString).deletingLastPathComponent   // e.g. /opt/homebrew/bin
    let base = "\(prefix):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    let inherited = env["PATH"].map { ":\($0)" } ?? ""
    env["PATH"] = base + inherited
    if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
    if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
    env["HOMEBREW_NO_AUTO_UPDATE"] = "1"   // explicit `brew update` still works
    env["HOMEBREW_NO_ENV_HINTS"] = "1"
    return env
}()

/// Reads a pipe to the end, calling `onLine` for each complete line as it arrives.
private func drain(_ handle: FileHandle, onLine: (@Sendable (String) -> Void)?) -> Data {
    guard let onLine else { return handle.readDataToEndOfFile() }
    var all = Data()
    var pending = [UInt8]()
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        all.append(chunk)
        for byte in chunk {
            if byte == 0x0A {
                onLine(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
            }
        }
    }
    if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
    return all
}

/// Runs brew and returns its stdout. `timeout: nil` never kills it — used for
/// installs/upgrades/uninstalls, where killing brew mid-run is worse than waiting.
/// `onLine` receives every stdout and stderr line as it's printed (brew reports
/// download progress on stderr), for live progress.
private func brew(_ args: [String], timeout: TimeInterval? = 30,
                  onLine: (@Sendable (String) -> Void)? = nil) async -> BrewResult {
    await withCheckedContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = args
        process.environment = brewEnvironment
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            continuation.resume(returning: BrewResult(output: "", errorOutput: "Error: Couldn't run \(brewPath)", exitCode: 1))
            return
        }

        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }

        // Drain stdout and stderr while brew runs. Reading only after it exits
        // deadlocks once either passes the 64 KB pipe buffer (e.g. `brew info` over
        // ~15 casks): brew blocks writing, so it never exits until the timeout.
        let stderrBox = StderrBox()
        let stderrDone = DispatchGroup()
        stderrDone.enter()
        DispatchQueue.global().async {
            stderrBox.data = drain(errPipe.fileHandleForReading, onLine: onLine)
            stderrDone.leave()
        }
        DispatchQueue.global().async {
            let data = drain(pipe.fileHandleForReading, onLine: onLine)
            stderrDone.wait()
            process.waitUntilExit()
            continuation.resume(returning: BrewResult(
                output: String(data: data, encoding: .utf8) ?? "",
                errorOutput: String(data: stderrBox.data, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            ))
        }
    }
}

extension String {
    var lines: [String] {
        split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
