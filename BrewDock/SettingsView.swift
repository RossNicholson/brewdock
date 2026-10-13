import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var brewService: BrewService
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var loginItemError: String? = nil
    @State private var checkedUpToDate = false
    @AppStorage(UpdateNotifier.enabledKey) private var notifyAboutUpdates = false
    @State private var notificationError: String? = nil
    @State private var cleanup: CleanupState = .measuring

    private enum CleanupState: Equatable {
        case measuring, reclaimable(String), nothing, cleaning, done(String), failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopoverHeader(title: "Settings", subtitle: "BrewDock preferences")
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.display(17, relativeTo: .headline))
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.text)
                        Text("Start BrewDock when you log in")
                            .font(.mono(9.5))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .tint(AppColors.toggle)
                .controlSize(.small)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.mono(9.5))
                        .foregroundStyle(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .card()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { notifyAboutUpdates },
                    set: { setNotifications($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update alerts")
                            .font(.display(17, relativeTo: .headline))
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.text)
                        Text("Notify me when new versions are out")
                            .font(.mono(9.5))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(AppColors.toggle)
                if let notificationError {
                    Text(notificationError)
                        .font(.mono(9.5))
                        .foregroundStyle(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .card()

            cleanupCard

            if brewService.selfUpdateAvailable {
                ColorBlockButton(
                    title: brewService.isUpdatingSelf ? "Updating…" : "Update BrewDock",
                    detail: "A new version is ready. BrewDock will restart.",
                    fill: AppColors.peach, symbol: "arrow.up"
                ) {
                    Task { await brewService.updateSelf() }
                }
                .disabled(brewService.isUpdatingSelf)
            } else {
                ColorBlockButton(
                    title: brewService.isCheckingSelfUpdate ? "Checking…" : "Check for updates",
                    detail: checkedUpToDate ? "BrewDock is up to date." : "See if a new version of BrewDock is out",
                    fill: checkedUpToDate ? AppColors.mint : AppColors.butter,
                    symbol: checkedUpToDate ? "checkmark" : "arrow.clockwise"
                ) {
                    checkedUpToDate = false
                    Task {
                        await brewService.checkSelfUpdate()
                        checkedUpToDate = !brewService.selfUpdateAvailable
                    }
                }
                .disabled(brewService.isCheckingSelfUpdate)
            }
        }
        .popoverChrome()
        .task { await measureCleanup() }
    }

    /// "Free up space": measured when Settings opens, cleaned on click
    private var cleanupCard: some View {
        let detail: String
        switch cleanup {
        case .measuring: detail = "Checking old versions and downloads…"
        case .reclaimable(let size): detail = "Old versions and downloads use \(size)"
        case .nothing: detail = "Nothing to clean up"
        case .cleaning: detail = "Cleaning up…"
        case .done(let message): detail = message
        case .failed(let message): detail = message
        }
        let canClean: Bool
        if case .reclaimable = cleanup { canClean = true } else { canClean = false }
        return ColorBlockButton(
            title: "Free up space",
            detail: detail,
            fill: { if case .failed = cleanup { return AppColors.coral }; if case .done = cleanup { return AppColors.mint }; return AppColors.lilac }(),
            symbol: { if case .done = cleanup { return "checkmark" }; return "sparkles" }()
        ) {
            Task {
                cleanup = .cleaning
                let (ok, message) = await brewService.cleanup()
                cleanup = ok ? .done(message) : .failed(message)
            }
        }
        .disabled(!canClean)
    }

    private func measureCleanup() async {
        cleanup = .measuring
        cleanup = await brewService.measureCleanup().map { .reclaimable($0) } ?? .nothing
    }

    private func setNotifications(_ enabled: Bool) {
        notificationError = nil
        guard enabled else { notifyAboutUpdates = false; return }
        Task {
            if await UpdateNotifier.requestPermission() {
                notifyAboutUpdates = true
            } else {
                notifyAboutUpdates = false
                notificationError = "Allow BrewDock in System Settings → Notifications."
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if enabled && status == .requiresApproval {
            loginItemError = "Allow BrewDock in System Settings → General → Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
