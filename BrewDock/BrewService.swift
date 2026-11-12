import Foundation
import AppKit
import SwiftUI

struct BrewPackage: Identifiable {
    var id: String { "\(type):\(name)" }
    let name: String
    let version: String
    let type: PackageType
    var isOutdated: Bool = false
    /// A formula Homebrew installed only because something else needs it
    var isDependency: Bool = false
    /// "Don't update": a pinned formula (brew pin) or a cask held in BrewDock.
    /// Held packages never count as outdated, so Update all, the update count,
    /// the menu bar dot and notifications all skip them.
    var isHeld: Bool = false
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
    /// Packages being updated or removed, by `BrewPackage.id` ("cask:foo"), so
    /// a cask and a formula with the same name don't share them
    @Published var updatingPackages: Set<String> = []
    @Published var removingPackages: Set<String> = []
    @Published var installingPackages: Set<String> = []
    @Published var managingServices: Set<String> = []
    /// Latest progress label per package being installed/updated/removed (by
    /// `BrewPackage.id`, or `DiscoverPackage.id` for installs), e.g.
    /// "Downloading…". `allUpdatesKey` holds "Update all" progress.
    @Published var progress: [String: String] = [:]
    nonisolated static let allUpdatesKey = "*all*"
    /// Settings toggle: also treat casks that update themselves (Chrome, Slack…)
    /// as outdated. Homebrew skips them by default.
    nonisolated static let includeAutoUpdatingKey = "includeAutoUpdatingApps"
    /// Casks the user chose not to update (Homebrew can only pin formulae)
    nonisolated static let heldCasksKey = "heldCasks"
    private var heldCasks: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.heldCasksKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: Self.heldCasksKey) }
    }
    private var greedyFlags: [String] {
        UserDefaults.standard.bool(forKey: Self.includeAutoUpdatingKey) ? ["--greedy-auto-updates"] : []
    }
    /// Message for the toast at the bottom of the panel: `lastError` in coral,
    /// `lastNotice` (successes) in mint. Each assignment bumps `toastSerial`, so
    /// the same message twice in a row still shows (and restarts the timer).
    @Published var lastError: String? = nil {
        didSet { if lastError != nil { toastIsError = true; toastSerial &+= 1 } }
    }
    @Published var lastNotice: String? = nil {
        didSet { if lastNotice != nil { toastIsError = false; toastSerial &+= 1 } }
    }
    @Published private(set) var toastSerial = 0
    private(set) var toastIsError = true

    /// "Remove unlisted" packages waiting for the user to confirm. Shown by the
    /// main panel: the Brewfile popover closes as soon as the file picker opens.
    @Published var cleanupProposal: CleanupProposal? = nil

    struct CleanupProposal: Identifiable {
        let id = UUID()
        let path: String
        let packages: [String]
    }

    /// Reports a Brewfile result in the panel's toast
    func report(_ result: (success: Bool, message: String)) {
        if result.success { lastNotice = result.message } else { lastError = result.message }
    }
    @Published var isBrewfileWorking = false
    @Published var selfUpdateAvailable: Bool = false
    @Published var isCheckingSelfUpdate: Bool = false
    @Published var isUpdatingSelf: Bool = false
    nonisolated static let selfCaskName = "brewdock"
    /// BrewDock's cask by its full name. Homebrew 7 refuses short-name commands
    /// for casks from untrusted taps, but runs (and trusts) a fully named one,
    /// so the update check and self-update always use this.
    nonisolated static let selfCaskFullName = "rossnicholson/tap/brewdock"
    /// Packages Homebrew refused to load until their tap is trusted (Homebrew 7+)
    @Published var untrusted: [UntrustedTarget] = []
    /// macOS stopped an update changing an app in place, so Homebrew deleted
    /// and reinstalled it, which can reset that app's settings. Turning on
    /// BrewDock in App Management fixes it.
    @Published var needsAppManagement = false
    nonisolated static let appManagementDismissedKey = "appManagementCardDismissed"
    nonisolated static let appManagementSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
    /// Untrusted packages found by a failed action (kept across refreshes)
    private var untrustedFromActions: [UntrustedTarget] = []
    /// Action to run again once its package is trusted, keyed by full name
    private var retryAfterTrust: [String: @MainActor () async -> Void] = [:]
    /// What the last successful `brew outdated` reported, kept when a later one
    /// fails, so a failed check never looks like "everything's up to date"
    private var outdatedFormulae: Set<String> = []
    private var outdatedCasks: Set<String> = []
    /// Casks pinned on the command line (`brew pin --cask`, Homebrew 7+)
    private var pinnedCasks: Set<String> = []
    /// Callers of refresh(force: true) waiting for the refresh already running
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    /// "Remember my apps": what your other Macs have that this one doesn't
    @Published var otherMacs: [OtherMacGroup] = []
    /// Banner offering "Remember my apps" until the user turns it on or says no
    @Published var libraryOffer: LibraryOffer = .none
    enum LibraryOffer: Equatable {
        case none
        /// Lists from your other Macs are already in iCloud Drive (a new Mac)
        case welcome(from: String, count: Int)
        /// Nothing found yet: offer to start keeping this Mac's list
        case invite
    }
    /// A re-read queued while iCloud Drive downloads another Mac's list
    private var libraryRecheck: Task<Void, Never>? = nil
    /// Why this Mac's list couldn't be saved to iCloud Drive, for Settings
    @Published var libraryError: String? = nil
    /// Packages in the list last saved to iCloud Drive, so it's only rewritten
    /// when something was installed or removed
    private var savedLibraryNames: Set<String>? = nil
    /// Whether the last refresh listed casks and formulae without errors. A
    /// failed listing must never be saved as "this Mac has nothing".
    private var lastListingSucceeded = false
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

    /// A forced refresh always returns with the list as it is now: if one is
    /// already running, it waits for that to go round again.
    func refresh(force: Bool = false) async {
        if isLoading {
            guard force else { return }
            refreshQueued = true
            await withCheckedContinuation { refreshWaiters.append($0) }
            return
        }
        // The panel triggers refresh on every open; skip if we refreshed recently
        // so reopening feels instant. The manual refresh button and every
        // install/update/uninstall pass force: true.
        if !force, Date().timeIntervalSince(lastRefresh) < Self.refreshTTL { return }
        isLoading = true
        defer {
            isLoading = false
            let waiters = refreshWaiters
            refreshWaiters = []
            waiters.forEach { $0.resume() }
        }
        repeat {
            repeat {
                refreshQueued = false
                await loadPackages()
            } while refreshQueued
            await syncLibrary()
        } while refreshQueued
    }

    /// Saves this Mac's list to iCloud Drive if it changed, then reads the other
    /// Macs' lists. Runs after every refresh while "Remember my apps" is on.
    func syncLibrary(force: Bool = false) async {
        let enabled = UserDefaults.standard.bool(forKey: MacLibrary.enabledKey)
        guard MacLibrary.isICloudDriveOn else {
            otherMacs = []
            libraryOffer = .none
            if enabled { libraryError = "Turn on iCloud Drive in System Settings → Apple Account → iCloud." }
            return
        }
        guard enabled else {
            otherMacs = []
            await offerLibrary()
            return
        }
        libraryOffer = .none
        let names = Set(casks.map { "cask:\($0.name)" } + formulae.filter { !$0.isDependency }.map { "formula:\($0.name)" })
        if lastListingSucceeded, force || names != savedLibraryNames {
            let info = await brew(["info", "--json=v2", "--installed"], timeout: 60)
            if info.exitCode == 0, let entries = MacLibrary.entries(fromInstalledJSON: info.output) {
                do {
                    try MacLibrary.write(MacSnapshot(macName: MacLibrary.macName, updated: Date(), packages: entries))
                    savedLibraryNames = names
                    libraryError = nil
                } catch {
                    libraryError = "Couldn't save to iCloud Drive: \(error.localizedDescription)"
                }
            }
        }
        otherMacs = readOtherMacs()
    }

    /// What the other Macs' lists in iCloud Drive offer this one
    private func readOtherMacs() -> [OtherMacGroup] {
        let (snapshots, stillDownloading) = MacLibrary.otherSnapshots()
        if stillDownloading { recheckLibrarySoon() }
        return MacLibrary.missing(
            from: snapshots,
            installedCasks: Set(casks.map(\.name)),
            installedFormulae: Set(formulae.map(\.name)),
            dismissed: Set(UserDefaults.standard.stringArray(forKey: MacLibrary.dismissedKey) ?? []))
    }

    /// iCloud Drive is still fetching another Mac's list: look again in a bit,
    /// so a new Mac's banner appears without reopening the panel
    private func recheckLibrarySoon() {
        guard libraryRecheck == nil else { return }
        libraryRecheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.libraryRecheck = nil
            await self.syncLibrary()
        }
    }

    /// While "Remember my apps" is off and the user hasn't said no: if other
    /// Macs' lists are in iCloud Drive (a new Mac), offer them; otherwise offer
    /// to start keeping this Mac's list. Only reads, never writes.
    private func offerLibrary() async {
        guard !UserDefaults.standard.bool(forKey: MacLibrary.decidedKey), lastListingSucceeded else {
            libraryOffer = .none
            return
        }
        let groups = readOtherMacs()
        let count = groups.reduce(0) { $0 + $1.packages.count }
        libraryOffer = groups.isEmpty ? .invite
            : .welcome(from: groups.count == 1 ? groups[0].macName : "your other Macs", count: count)
    }

    /// The banner's "Turn on" / "Show me"
    func acceptLibraryOffer() async {
        UserDefaults.standard.set(true, forKey: MacLibrary.enabledKey)
        UserDefaults.standard.set(true, forKey: MacLibrary.decidedKey)
        libraryOffer = .none
        await syncLibrary(force: true)
    }

    /// The banner's ×: don't offer again (Settings still has the toggle)
    func declineLibraryOffer() {
        UserDefaults.standard.set(true, forKey: MacLibrary.decidedKey)
        libraryOffer = .none
    }

    /// Turning "Remember my apps" off removes this Mac's list, so the other Macs
    /// stop suggesting its apps
    func stopRememberingApps() {
        MacLibrary.removeOwnSnapshot()
        savedLibraryNames = nil
        libraryError = nil
        otherMacs = []
    }

    /// "Don't suggest this": hides packages from other Macs on this one
    func dismissFromOtherMacs(_ tokens: [String]) {
        let key = MacLibrary.dismissedKey
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: key) ?? []).union(tokens)
        UserDefaults.standard.set(dismissed.sorted(), forKey: key)
        otherMacs = otherMacs.compactMap { group in
            let left = group.packages.filter { !dismissed.contains($0.token) }
            return left.isEmpty ? nil : OtherMacGroup(macName: group.macName, packages: left)
        }
    }

    /// "Install all" for one of your other Macs. One at a time: brew installs
    /// can't run side by side.
    func installAll(_ packages: [DiscoverPackage]) async {
        for package in packages where !Task.isCancelled {
            await install(package)
        }
    }

    private func loadPackages() async {
        async let caskResult    = brew(["list", "--cask", "--versions"])
        async let formulaResult = brew(["list", "--formula", "--versions"])
        // JSON, because the plain list names formulae by tap and alias
        // ("python" for python@3.13), which `brew list` doesn't
        async let outdatedResult = brew(["outdated", "--json=v2"] + greedyFlags, timeout: 120)
        async let requestedResult = brew(["list", "--formula", "--installed-on-request"])
        async let pinnedFormulaResult = brew(["list", "--pinned", "--formula"])
        async let pinnedCaskResult = brew(["list", "--pinned", "--cask"])

        let (caskRes, formulaRes, outdatedRes, requestedRes, pinnedFormulaRes, pinnedCaskRes) =
            await (caskResult, formulaResult, outdatedResult, requestedResult, pinnedFormulaResult, pinnedCaskResult)

        lastListingSucceeded = caskRes.exitCode == 0 && formulaRes.exitCode == 0
        if let outdated = BrewParse.outdated(fromJSON: outdatedRes.output) {
            outdatedFormulae = outdated.formulae
            outdatedCasks = outdated.casks
        }
        let pinnedFormulae = pinnedFormulaRes.exitCode == 0 ? Set(pinnedFormulaRes.output.lines) : []
        // Older Homebrew can't pin casks and refuses --cask here
        pinnedCasks = pinnedCaskRes.exitCode == 0 ? Set(pinnedCaskRes.output.lines) : []
        let allHeldCasks = heldCasks.union(pinnedCasks)
        let casksToUpdate = outdatedCasks.subtracting(allHeldCasks)
        let formulaeToUpdate = outdatedFormulae.subtracting(pinnedFormulae)
        let listedUntrusted = [caskRes, formulaRes, outdatedRes]
            .flatMap { BrewParse.untrustedTargets(fromStderr: $0.errorOutput) }
        untrusted = (listedUntrusted + untrustedFromActions).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }

        var parsedCasks = BrewParse.packages(from: caskRes.output, type: .cask, outdated: casksToUpdate)
        // brew refuses to list any casks while one installed cask is untrusted;
        // read the Caskroom folder instead so the Apps tab still works.
        if caskRes.exitCode != 0 && parsedCasks.isEmpty && !listedUntrusted.isEmpty {
            parsedCasks = BrewParse.caskroomPackages(caskroomEntries(), outdated: casksToUpdate)
        }

        if !parsedCasks.isEmpty {
            // `brew info` would refuse the whole batch over one untrusted cask
            let untrustedNames = Set(untrusted.map(\.shortName))
            await resolveAppPaths(forCaskNames: parsedCasks.map(\.name).filter { !untrustedNames.contains($0) })
            parsedCasks = parsedCasks.map { pkg in
                var p = pkg
                if let path = appPathCache[pkg.name] {
                    p.resolvedAppPath = path
                    p.appIcon = NSWorkspace.shared.icon(forFile: path)
                }
                return p
            }
        }

        self.casks = parsedCasks.map { var p = $0; p.isHeld = allHeldCasks.contains(p.name); return p }
        // Keep Settings in step with the list: if the list shows BrewDock as
        // outdated, offer the update without waiting for the next check, and
        // never while it's held.
        if isSelfHeld {
            selfUpdateAvailable = false
        } else if self.casks.contains(where: { $0.isBrewDock && $0.isOutdated }) {
            selfUpdateAvailable = true
        }
        var parsedFormulae = BrewParse.packages(from: formulaRes.output, type: .formula, outdated: formulaeToUpdate)
        // Mark dependencies, unless brew couldn't say (then show everything as yours)
        if requestedRes.exitCode == 0 {
            let requested = Set(requestedRes.output.lines)
            parsedFormulae = parsedFormulae.map { var p = $0; p.isDependency = !requested.contains(p.name); return p }
        }
        self.formulae = parsedFormulae.map { var p = $0; p.isHeld = pinnedFormulae.contains(p.name); return p }
        lastRefresh = Date()
    }

    /// Caskroom contents: token → version folder names
    private func caskroomEntries() -> [String: [String]] {
        let prefix = ((brewPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let caskroom = (prefix as NSString).appendingPathComponent("Caskroom")
        let fm = FileManager.default
        var entries: [String: [String]] = [:]
        for token in (try? fm.contentsOfDirectory(atPath: caskroom)) ?? [] where !token.hasPrefix(".") {
            entries[token] = (try? fm.contentsOfDirectory(atPath: (caskroom as NSString).appendingPathComponent(token))) ?? []
        }
        return entries
    }

    /// If brew refused `result` because of an untrusted tap, remember the package
    /// (shown as a banner) and the action to retry once it's trusted.
    private func noteUntrusted(_ result: BrewResult, retry: @escaping @MainActor () async -> Void) -> Bool {
        let targets = BrewParse.untrustedTargets(fromStderr: result.errorOutput)
        guard let first = targets.first else { return false }
        for target in targets where !untrustedFromActions.contains(target) { untrustedFromActions.append(target) }
        for target in targets where !untrusted.contains(target) { untrusted.append(target) }
        retryAfterTrust[first.name] = retry
        lastError = "\(first.shortName) needs trusting first — see the banner"
        return true
    }

    /// After a cask update: show the App Management card if Homebrew had to
    /// reinstall an app, and hide it once an update goes through in place
    private func noteAppManagement(_ result: BrewResult) {
        if BrewParse.lacksAppManagement(result.errorOutput + result.output) {
            needsAppManagement = !UserDefaults.standard.bool(forKey: Self.appManagementDismissedKey)
        } else if result.exitCode == 0 {
            needsAppManagement = false
        }
    }

    func dismissAppManagement() {
        UserDefaults.standard.set(true, forKey: Self.appManagementDismissedKey)
        needsAppManagement = false
    }

    /// Runs `brew trust` for one package (the user confirmed in the banner), then
    /// refreshes and retries whatever action was refused.
    func trust(_ target: UntrustedTarget) async {
        let result = await brew(["trust", target.kind == .cask ? "--cask" : "--formula", target.name], timeout: 60)
        guard result.exitCode == 0 else {
            lastError = result.failureMessage("Couldn't trust \(target.shortName)")
            return
        }
        untrustedFromActions.removeAll { $0 == target }
        untrusted.removeAll { $0 == target }
        let retry = retryAfterTrust.removeValue(forKey: target.name)
        await refresh(force: true)
        await retry?()
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

    /// "Don't update" / "Allow updates". Formulae use `brew pin`, which the
    /// command line respects too; casks can't be pinned, so BrewDock holds them.
    func setHeld(_ package: BrewPackage, _ held: Bool) async {
        if package.type == .formula {
            let result = await brew([held ? "pin" : "unpin", package.name])
            if result.exitCode != 0 {
                lastError = result.failureMessage("Couldn't \(held ? "hold" : "release") \(package.name)")
            }
        } else if held {
            heldCasks.insert(package.name)
        } else {
            heldCasks.remove(package.name)
            // Pinned on the command line: BrewDock's hold isn't the only one
            if pinnedCasks.contains(package.name) {
                let result = await brew(["unpin", "--cask", package.name])
                if result.exitCode != 0 {
                    lastError = result.failureMessage("Couldn't release \(package.name)")
                }
            }
        }
        await refresh(force: true)
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
        updatingPackages.insert(package.id)
        defer { updatingPackages.remove(package.id) }
        let flags = package.type == .cask ? ["--cask"] + greedyFlags : ["--formula"]
        let result = await brew(["upgrade"] + flags + [package.name], timeout: nil,
                                onLine: reportProgress(to: package.id))
        if package.type == .cask { noteAppManagement(result) }
        if result.exitCode != 0, noteUntrusted(result, retry: { [weak self] in await self?.upgrade(package) }) { return }
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't update \(package.name)") }
        await refresh(force: true)
    }

    func install(_ package: DiscoverPackage) async {
        installingPackages.insert(package.id)
        defer { installingPackages.remove(package.id) }
        let flag = package.type == .cask ? "--cask" : "--formula"
        let result = await brew(["install", flag, package.installToken], timeout: nil,
                                onLine: reportProgress(to: package.id))
        if result.exitCode != 0, noteUntrusted(result, retry: { [weak self] in await self?.install(package) }) { return }
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't install \(package.displayName)") }
        await refresh(force: true)
    }

    func uninstall(_ package: BrewPackage) async {
        if package.isBrewDock {
            if !launchDetachedSelfBrew(.uninstall) { lastError = "Couldn't start the uninstaller." }
            return
        }
        removingPackages.insert(package.id)
        defer { removingPackages.remove(package.id) }
        let flag = package.type == .cask ? "--cask" : "--formula"
        let result = await brew(["uninstall", flag, package.name], timeout: nil,
                                onLine: reportProgress(to: package.id))
        if result.exitCode != 0, noteUntrusted(result, retry: { [weak self] in await self?.uninstall(package) }) { return }
        if result.exitCode != 0 { lastError = result.failureMessage("Couldn't uninstall \(package.name)") }
        await refresh(force: true)
    }

    // Called on launch — quick check against local cache, no network fetch
    func checkSelfUpdateSilent() async {
        let result = await brew(["outdated", "--cask", Self.selfCaskFullName])
        selfUpdateAvailable = Self.listsSelf(result.output) && !isSelfHeld
    }

    // Called when the user explicitly clicks "Check for Updates" — runs brew update first.
    // `showProgress: false` lets the periodic background timer refresh quietly.
    func checkSelfUpdate(showProgress: Bool = true) async {
        if showProgress { isCheckingSelfUpdate = true }
        defer { if showProgress { isCheckingSelfUpdate = false } }
        _ = await brew(["update"], timeout: 60)
        let result = await brew(["outdated", "--cask", Self.selfCaskFullName])
        selfUpdateAvailable = Self.listsSelf(result.output) && !isSelfHeld
    }

    /// The user chose "Don't update" on BrewDock itself
    var isSelfHeld: Bool {
        heldCasks.contains(Self.selfCaskName) || pinnedCasks.contains(Self.selfCaskName)
    }

    /// Whether `brew outdated` output names BrewDock (short or full name)
    nonisolated static func listsSelf(_ output: String) -> Bool {
        output.lines.contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line == selfCaskName || line == selfCaskFullName
        }
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
        // The path first: by bundle ID, macOS may pick another copy (an old
        // download, a dev build) over the one brew just replaced
        let reopen = "open \"\(appPath)\" || open -b \"\(bundleID)\""
        let onSuccess = command == .upgrade ? reopen : ":"

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
        echo "[$(date)] running brew \(command.rawValue) --cask \(Self.selfCaskFullName)" >> "$LOG"
        "\(brewPath)" \(command.rawValue) --cask \(Self.selfCaskFullName) >> "$LOG" 2>&1
        status=$?
        echo "[$(date)] brew exited with status $status" >> "$LOG"
        if [ "$status" -eq 0 ]; then
            \(onSuccess)
        else
            osascript -e 'display notification "BrewDock \(command.rawValue) failed — see \(logURL.path)" with title "BrewDock"' >/dev/null 2>&1 || true
            # Nothing changed, so bring the menu bar app back
            \(reopen)
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
        let outdatedCasks = casks.filter { $0.isOutdated && !$0.isBrewDock }
        let outdatedFormulae = formulae.filter(\.isOutdated)
        let selfOutdated = casks.contains { $0.isOutdated && $0.isBrewDock }
        let ids = (outdatedCasks + outdatedFormulae).map(\.id)
        updatingPackages.formUnion(ids)
        var failure: BrewResult? = nil
        var needsTrust = false
        let retry: @MainActor () async -> Void = { [weak self] in await self?.upgradeAll() }
        /// Notes a failed batch: untrusted packages go to the banner (and are
        /// retried once trusted), anything else is the failure to report
        func note(_ result: BrewResult) {
            guard result.exitCode != 0 else { return }
            if noteUntrusted(result, retry: retry) {
                needsTrust = true
            } else {
                failure = failure ?? result
            }
        }
        if !outdatedFormulae.isEmpty {
            note(await brew(["upgrade", "--formula"] + outdatedFormulae.map(\.name), timeout: nil,
                            onLine: reportProgress(to: Self.allUpdatesKey)))
        }
        if !outdatedCasks.isEmpty {
            let result = await brew(["upgrade", "--cask"] + greedyFlags + outdatedCasks.map(\.name), timeout: nil,
                                    onLine: reportProgress(to: Self.allUpdatesKey))
            noteAppManagement(result)
            note(result)
        }
        updatingPackages.subtract(ids)
        if let failure {
            lastError = failure.failureMessage("Some updates failed")
                + (needsTrust ? ". A package also needs trusting — see the banner" : "")
        }
        if selfOutdated && failure == nil && !needsTrust {
            await updateSelf()
            return
        }
        await refresh(force: true)
    }

    /// Settings toggle, off by default: update everything every 10 minutes
    nonisolated static let autoUpdateKey = "autoUpdateEverything"
    nonisolated static let autoUpdateInterval: TimeInterval = 10 * 60

    /// Whether anything is installing, updating, removing or refreshing
    var isBusy: Bool {
        isLoading || isBrewfileWorking || isUpdatingSelf || !updatingPackages.isEmpty
            || !removingPackages.isEmpty || !installingPackages.isEmpty
    }

    /// One unattended Auto-update run: fetch Homebrew's latest index, then
    /// upgrade everything outdated except apps that are open (replacing a
    /// running app can break it; they're picked up once quit), untrusted casks
    /// and BrewDock itself, which the caller updates last since that restarts
    /// the app. Stays quiet on failure, as the next run tries again. Returns
    /// the names that were updated.
    func autoUpdate() async -> [String] {
        guard !isBusy else { return [] }
        _ = await brew(["update"], timeout: 120)
        await refresh(force: true)
        guard !isBusy else { return [] }

        func isUntrusted(_ package: BrewPackage) -> Bool {
            untrusted.contains { $0.kind == package.type && $0.shortName == package.name }
        }
        let outdatedCasks = casks.filter {
            $0.isOutdated && !$0.isBrewDock && !isUntrusted($0) && $0.runningApplication == nil
        }
        let outdatedFormulae = formulae.filter { $0.isOutdated && !isUntrusted($0) }
        let attempted = outdatedCasks + outdatedFormulae
        guard !attempted.isEmpty else { return [] }

        updatingPackages.formUnion(attempted.map(\.id))
        if !outdatedFormulae.isEmpty {
            _ = await brew(["upgrade", "--formula"] + outdatedFormulae.map(\.name), timeout: nil,
                           onLine: reportProgress(to: Self.allUpdatesKey))
        }
        if !outdatedCasks.isEmpty {
            let result = await brew(["upgrade", "--cask"] + greedyFlags + outdatedCasks.map(\.name), timeout: nil,
                                    onLine: reportProgress(to: Self.allUpdatesKey))
            noteAppManagement(result)
        }
        updatingPackages.subtract(attempted.map(\.id))
        await refresh(force: true)
        // Brew carries on past a failed package, so check what actually updated
        let stillOutdated = Set((casks + formulae).filter(\.isOutdated).map(\.id))
        return attempted.filter { !stillOutdated.contains($0.id) }.map(\.name)
    }

    func brewfileDump(to path: String) async -> (success: Bool, message: String) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "dump", "--file=\(path)", "--force"], timeout: 300)
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
        let missing = BrewParse.bundleCheckMissing(fromStderr: result.errorOutput)
        if !missing.isEmpty { return (false, "Missing: \(missing.joined(separator: ", "))") }
        // Exit 1 with no list: brew couldn't check at all (a bad file, a timeout)
        return (false, result.failureMessage("Couldn't check the Brewfile"))
    }

    /// What "Remove unlisted" would remove, or why brew couldn't say. The dry
    /// run exits 1 when it finds something, so only an error line or a
    /// timeout counts as failing.
    func brewfileCleanupPreview(at path: String) async -> (packages: [String], error: String?) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "cleanup", "--file=\(path)"], timeout: 300)
        let packages = BrewParse.cleanupCandidates(fromOutput: result.output)
        if result.timedOut || (packages.isEmpty && result.errorOutput.contains("Error:")) {
            return ([], result.failureMessage("Couldn't read the Brewfile"))
        }
        return (packages, nil)
    }

    func brewfileCleanup(at path: String) async -> (success: Bool, message: String) {
        isBrewfileWorking = true
        defer { isBrewfileWorking = false }
        let result = await brew(["bundle", "cleanup", "--file=\(path)", "--force"], timeout: nil)
        await refresh(force: true)
        guard result.exitCode == 0 else { return (false, result.failureMessage("Cleanup failed")) }
        return (true, "Cleanup complete.")
    }

    /// Searches all of Homebrew (not just the curated Discover list), returning up
    /// to `limit` formulae and `limit` casks with their descriptions.
    func searchHomebrew(_ query: String, limit: Int = 15) async -> [DiscoverPackage] {
        async let formulaSearch = brew(["search", "--formula", query])
        async let caskSearch = brew(["search", "--cask", query])
        let curated = Set(DiscoverCatalog.all.map(\.id))
        let (formulaRes, caskRes) = await (formulaSearch, caskSearch)
        let formulae = BrewParse.searchNames(fromOutput: formulaRes.output).filter { !curated.contains($0) }.prefix(limit)
        let casks = BrewParse.searchNames(fromOutput: caskRes.output).filter { !curated.contains($0) }.prefix(limit)
        guard !Task.isCancelled else { return [] }

        async let formulaInfo = formulae.isEmpty ? BrewResult(output: "", exitCode: 0)
            : brew(["info", "--json=v2", "--formula"] + formulae)
        async let caskInfo = casks.isEmpty ? BrewResult(output: "", exitCode: 0)
            : brew(["info", "--json=v2", "--cask"] + casks)
        let (fInfo, cInfo) = await (formulaInfo, caskInfo)
        let summaries = BrewParse.packageSummaries(fromJSON: fInfo.output) + BrewParse.packageSummaries(fromJSON: cInfo.output)
        // Keep brew's relevance order: formulae then casks, as searched
        let order = Array(formulae) + Array(casks)
        return summaries
            .sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
            .map { DiscoverPackage(searchResult: $0.id, displayName: $0.name, description: $0.desc, type: $0.type) }
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
    /// Killed for running past its timeout
    var timedOut = false

    /// "Couldn't update git: <brew's error>", or just the first part when brew
    /// gave no reason
    func failureMessage(_ base: String) -> String {
        if timedOut { return "\(base): Homebrew took too long" }
        return BrewParse.errorSummary(fromStderr: errorOutput).map { "\(base): \($0)" } ?? base
    }
}

/// Output collected by a reading thread. Locked, because a timed-out run reads
/// it while a child brew left behind may still be writing.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()
    var data: Data {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Every process started by `pid`, and theirs, deepest last
private func descendants(of pid: pid_t) -> [pid_t] {
    var buffer = [pid_t](repeating: 0, count: 256)
    let count = Int(proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size)))
    guard count > 0 else { return [] }
    let children = buffer.prefix(min(count, buffer.count)).filter { $0 > 0 }
    return children + children.flatMap { descendants(of: $0) }
}

/// Stops brew and whatever it started (git, curl): those inherit its output
/// pipes, so killing brew alone leaves the pipes open and the read hanging
private func stop(_ process: Process, exited: DispatchSemaphore) {
    let pid = process.processIdentifier
    // Collected first: once brew is gone, its children belong to launchd
    for child in descendants(of: pid) { kill(child, SIGTERM) }
    process.terminate()
    if exited.wait(timeout: .now() + 3) == .timedOut {
        for child in descendants(of: pid) { kill(child, SIGKILL) }
        kill(pid, SIGKILL)
        exited.wait()
    }
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
    // Makes Homebrew say when macOS's App Management setting stops it updating
    // an app in place, so BrewDock can explain (see needsAppManagement)
    env["HOMEBREW_NO_APP_MANAGEMENT_PERMISSIONS_PROMPT"] = "1"
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
    // Its own thread, as it blocks while brew runs
    await withCheckedContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(returning: runBrew(args, timeout: timeout, onLine: onLine))
        }
    }
}

private func runBrew(_ args: [String], timeout: TimeInterval?,
                     onLine: (@Sendable (String) -> Void)?) -> BrewResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: brewPath)
    process.arguments = args
    process.environment = brewEnvironment
    let pipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = pipe
    process.standardError = errPipe
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }

    do {
        try process.run()
    } catch {
        return BrewResult(output: "", errorOutput: "Error: Couldn't run \(brewPath)", exitCode: 1)
    }

    // Drain stdout and stderr while brew runs. Reading only after it exits
    // deadlocks once either passes the 64 KB pipe buffer (e.g. `brew info` over
    // ~15 casks): brew blocks writing, so it never exits until the timeout.
    let outBox = OutputBox()
    let errBox = OutputBox()
    let read = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        outBox.data = drain(pipe.fileHandleForReading, onLine: onLine)
        read.signal()
    }
    Thread.detachNewThread {
        errBox.data = drain(errPipe.fileHandleForReading, onLine: onLine)
        read.signal()
    }

    var timedOut = false
    if let timeout {
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            stop(process, exited: exited)
        }
    } else {
        exited.wait()
    }
    // The output ends when brew exits, unless something it started is still
    // holding the pipes, so don't wait on that forever
    let grace: TimeInterval = timedOut ? 2 : 10
    _ = read.wait(timeout: .now() + grace)
    _ = read.wait(timeout: .now() + grace)
    return BrewResult(
        output: String(data: outBox.data, encoding: .utf8) ?? "",
        errorOutput: String(data: errBox.data, encoding: .utf8) ?? "",
        exitCode: timedOut ? -1 : process.terminationStatus,
        timedOut: timedOut
    )
}

extension String {
    var lines: [String] {
        split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
