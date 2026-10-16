import Foundation
import UserNotifications

/// Optional "updates ready" notifications from the background check. Each
/// package is announced once per new version: the set already announced is
/// remembered, so the same updates don't notify again every few hours.
@MainActor
enum UpdateNotifier {
    static let enabledKey = "notifyAboutUpdates"
    private static let announcedKey = "announcedOutdatedPackages"
    private static let notificationID = "brewdock-updates"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Asks macOS for permission. Returns whether notifications are allowed.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Call after a refresh with the currently outdated package names, most
    /// interesting first (the notification names the first few).
    static func notifyIfNew(outdated: [String]) {
        let defaults = UserDefaults.standard
        let current = Set(outdated)
        let announced = Set(defaults.stringArray(forKey: announcedKey) ?? [])
        // Keep only names still outdated, so a package that's updated and then
        // goes out of date again is announced again.
        defaults.set(Array(current), forKey: announcedKey)

        var seen = Set<String>()
        let fresh = outdated.filter { !announced.contains($0) && seen.insert($0).inserted }
        guard isEnabled, !fresh.isEmpty else { return }

        let message = message(fresh: fresh, total: current.count)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// After an Auto-update run that updated something. Awaited, so it's
    /// posted before a BrewDock self-update quits the app.
    static func notifyAutoUpdated(_ names: [String]) async {
        guard isEnabled, !names.isEmpty else { return }
        let message = autoUpdatedMessage(names)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        let request = UNNotificationRequest(identifier: "brewdock-auto-updated", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// "Updated 3 Homebrew packages" / "git, node and 1 more"
    nonisolated static func autoUpdatedMessage(_ names: [String]) -> (title: String, body: String) {
        let title = names.count == 1 ? "Updated 1 Homebrew package" : "Updated \(names.count) Homebrew packages"
        let shown = names.prefix(3).joined(separator: ", ")
        let rest = names.count - min(names.count, 3)
        return (title, shown + (rest > 0 ? " and \(rest) more" : ""))
    }

    /// "3 Homebrew updates ready" / "New: blender, node and 2 more"
    nonisolated static func message(fresh: [String], total: Int) -> (title: String, body: String) {
        let title = total == 1 ? "1 Homebrew update ready" : "\(total) Homebrew updates ready"
        let shown = fresh.prefix(3).joined(separator: ", ")
        let rest = fresh.count - min(fresh.count, 3)
        let body = "New: " + shown + (rest > 0 ? " and \(rest) more" : "")
        return (title, body)
    }
}
