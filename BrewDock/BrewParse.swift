import Foundation

/// Pure, side-effect-free parsing of Homebrew command output. Kept separate from
/// `BrewService` (which is `@MainActor` and owns app state) so the brittle bits —
/// the code most likely to break when Homebrew changes its output — can be unit
/// tested in isolation. No filesystem or process access lives here.
enum BrewParse {

    /// Parse `brew list --versions`. Each line is `name v1 v2 …`; keep the name and
    /// the remainder as the version string, flagging names present in `outdated`.
    static func packages(from output: String,
                         type: BrewPackage.PackageType,
                         outdated: Set<String>) -> [BrewPackage] {
        output.lines.compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let name = parts.first.map(String.init) else { return nil }
            let version = parts.count > 1 ? String(parts[1]) : ""
            return BrewPackage(name: name, version: version, type: type,
                               isOutdated: outdated.contains(name))
        }
    }

    /// Parse `brew services list --json` (far more robust than column-splitting the
    /// human-readable table, which mis-parses when a column is blank).
    static func services(fromJSON json: String) -> [HomebrewService] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let status = HomebrewService.Status(rawValue: (entry["status"] as? String) ?? "") ?? .unknown
            let user = entry["user"] as? String ?? ""
            return HomebrewService(name: name, status: status, user: user)
        }
    }

    /// Parse `brew info --json=v2 --cask` into `token → [candidate .app names]`.
    /// Casks with no app artifact (CLI-only) map to `[]`, so callers can tell
    /// "brew says there's no app" apart from "brew didn't answer". An app moved
    /// with `target:` is reported under its target name. The caller resolves
    /// which candidate actually exists on disk.
    static func caskAppNames(fromJSON json: String) -> [String: [String]] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = obj["casks"] as? [[String: Any]]
        else { return [:] }

        var result: [String: [String]] = [:]
        for cask in casks {
            guard let token = cask["token"] as? String else { continue }
            let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
            result[token] = artifacts.compactMap { artifact -> String? in
                guard let app = artifact["app"] as? [Any] else { return nil }
                let target = app.lazy.compactMap { ($0 as? [String: Any])?["target"] as? String }.first
                return target ?? app.first as? String
            }
        }
        return result
    }

    /// The one line worth showing from brew's stderr when a command fails: the
    /// first `Error:` line (without the prefix), else the last `Warning:`, else
    /// the last non-empty line. Nil when there's nothing useful.
    static func errorSummary(fromStderr stderr: String) -> String? {
        let lines = stderr.lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let line = lines.first { $0.hasPrefix("Error:") }
            ?? lines.last { $0.hasPrefix("Warning:") }
            ?? lines.last { !$0.hasPrefix("==>") }
        guard var summary = line else { return nil }
        for prefix in ["Error:", "Warning:"] where summary.hasPrefix(prefix) {
            summary = String(summary.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if summary.hasSuffix(".") { summary.removeLast() }
        if summary.count > 160 { summary = String(summary.prefix(157)) + "…" }
        return summary.isEmpty ? nil : summary
    }

    /// A short progress label for one line of brew install/upgrade/uninstall
    /// output, or nil for lines that aren't progress. Long names, URLs and
    /// bottle filenames are dropped so the label fits in a row.
    static func progressLabel(fromLine raw: String) -> String? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        // Download finished (Homebrew 5+ prints these on stderr): "✔︎ Bottle jq (1.7.1)"
        // Compare the scalar: "✔︎" carries a variation selector, so it's a different Character
        if line.unicodeScalars.first == "\u{2714}" {
            let words = line.split(separator: " ")
            guard words.count >= 3 else { return "Downloaded" }
            return "Downloaded \(words[2])"
        }
        guard line.hasPrefix("==> ") else { return nil }
        let words = line.dropFirst(4).split(separator: " ").map(String.init)
        guard let verb = words.first else { return nil }
        /// The package named after the verb, if it's a plain name (not "2 outdated…")
        func subject(skipping skip: Set<String> = []) -> String? {
            guard let word = words.dropFirst().first(where: { !skip.contains($0) }),
                  word.first?.isNumber == false, !word.hasSuffix(":"), !word.contains("/") else { return nil }
            return word
        }
        switch verb {
        case "Downloading": return "Downloading…"
        case "Fetching":
            if words.dropFirst().first == "downloads" { return "Downloading…" }
            return subject().map { "Fetching \($0)…" } ?? "Fetching…"
        case "Pouring": return "Unpacking…"
        case "Installing": return subject(skipping: ["Cask"]).map { "Installing \($0)…" } ?? "Installing…"
        case "Upgrading": return subject().map { "Upgrading \($0)…" }
        case "Moving": return "Moving to Applications…"
        case "Uninstalling": return "Uninstalling…"
        case "Removing": return "Removing…"
        case "Backing": return "Backing up…"
        case "Purging": return "Cleaning up…"
        case "Running": return line.contains("cleanup") ? "Cleaning up…" : nil
        case "Linking": return "Linking…"
        case "Verifying", "Checking": return "Checking…"
        default: return nil
        }
    }
}
