import Foundation
import SystemConfiguration

/// "Remember my apps": each Mac keeps a list of what you installed with Homebrew
/// in iCloud Drive, so BrewDock on your other Macs can offer the same apps and
/// tools, like a game library that follows you to a new computer. Nothing is
/// installed without you asking; other Macs just list what this one is missing.
struct MacSnapshot: Codable, Equatable {
    var macName: String
    var updated: Date
    var packages: [Entry]

    struct Entry: Codable, Hashable {
        /// The name to install by: tap-qualified outside Homebrew's own taps
        /// (e.g. "rossnicholson/tap/clawdbar"), so brew taps it automatically
        let token: String
        let name: String
        let desc: String
        let isCask: Bool

        /// The name `brew list` shows once it's installed
        var shortName: String { token.split(separator: "/").last.map(String.init) ?? token }
    }
}

/// What one other Mac has that this one doesn't
struct OtherMacGroup: Identifiable, Equatable {
    var id: String { macName }
    let macName: String
    let packages: [MacSnapshot.Entry]
}

enum MacLibrary {
    /// Settings toggle, off by default
    static let enabledKey = "rememberApps"
    /// Tokens the user said not to suggest on this Mac
    static let dismissedKey = "otherMacsDismissed"
    private static let macIDKey = "macLibraryID"
    /// Lists from Macs that haven't checked in for a year are ignored
    private static let staleAfter: TimeInterval = 365 * 24 * 60 * 60

    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static var isICloudDriveOn: Bool {
        FileManager.default.fileExists(atPath: iCloudDrive.path)
    }

    static var folder: URL {
        iCloudDrive.appendingPathComponent("BrewDock/Macs", isDirectory: true)
    }

    /// A random ID for this Mac, so renaming it doesn't leave a second list behind
    static var macID: String {
        if let id = UserDefaults.standard.string(forKey: macIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: macIDKey)
        return id
    }

    /// "Ross's MacBook Air", as set in System Settings → General → Sharing
    static var macName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Another Mac"
    }

    private static var ownFile: URL { folder.appendingPathComponent("\(macID).json") }

    static func write(_ snapshot: MacSnapshot) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: ownFile, options: .atomic)
    }

    /// Turning the setting off stops other Macs suggesting this one's apps
    static func removeOwnSnapshot() {
        try? FileManager.default.removeItem(at: ownFile)
    }

    /// Every other Mac's list. iCloud Drive can leave a file in the cloud as a
    /// ".name.json.icloud" placeholder; those are asked to download, and show up
    /// on a later refresh.
    static func otherSnapshots() -> [MacSnapshot] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshots: [MacSnapshot] = []
        for name in names where name != "\(macID).json" && name != ".\(macID).json.icloud" {
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                try? fm.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(real))
                continue
            }
            guard name.hasSuffix(".json"),
                  let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  let snapshot = try? decoder.decode(MacSnapshot.self, from: data),
                  Date().timeIntervalSince(snapshot.updated) < staleAfter else { continue }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    /// This Mac's list from `brew info --json=v2 --installed`: every cask except
    /// BrewDock, and the formulae you asked for (not their dependencies). Nil if
    /// brew's output can't be read, so a failed run never wipes the list.
    static func entries(fromInstalledJSON json: String) -> [MacSnapshot.Entry]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]],
              let casks = root["casks"] as? [[String: Any]] else { return nil }

        var entries: [MacSnapshot.Entry] = []
        for cask in casks {
            guard let token = cask["full_token"] as? String ?? cask["token"] as? String,
                  cask["token"] as? String != BrewService.selfCaskName else { continue }
            let name = (cask["name"] as? [String])?.first ?? token
            entries.append(.init(token: token, name: name, desc: cask["desc"] as? String ?? "", isCask: true))
        }
        for formula in formulae {
            guard let token = formula["full_name"] as? String ?? formula["name"] as? String else { continue }
            let installs = formula["installed"] as? [[String: Any]] ?? []
            guard installs.contains(where: { $0["installed_on_request"] as? Bool == true }) else { continue }
            entries.append(.init(token: token, name: formula["name"] as? String ?? token,
                                 desc: formula["desc"] as? String ?? "", isCask: false))
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// What the other Macs have that this one doesn't, one group per Mac (most
    /// recently used first), each package listed once
    static func missing(from snapshots: [MacSnapshot], installedCasks: Set<String>,
                        installedFormulae: Set<String>, dismissed: Set<String>) -> [OtherMacGroup] {
        var seen: Set<String> = []
        var groups: [OtherMacGroup] = []
        for snapshot in snapshots.sorted(by: { $0.updated > $1.updated }) {
            let packages = snapshot.packages.filter { entry in
                let installed = entry.isCask ? installedCasks : installedFormulae
                guard !installed.contains(entry.shortName), !dismissed.contains(entry.token) else { return false }
                return seen.insert(entry.token).inserted
            }
            if !packages.isEmpty { groups.append(OtherMacGroup(macName: snapshot.macName, packages: packages)) }
        }
        return groups
    }
}
