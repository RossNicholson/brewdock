import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var brewService: BrewService
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var loginItemError: String? = nil
    @State private var checkedUpToDate = false

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
