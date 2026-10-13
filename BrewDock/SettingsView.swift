import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var brewService: BrewService
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var loginItemError: String? = nil
    @State private var checkedUpToDate = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Settings")
                    .font(.title3).fontWeight(.semibold)
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                if brewService.selfUpdateAvailable {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A BrewDock update is available.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(brewService.isUpdatingSelf ? "Updating…" : "Update BrewDock…") {
                            Task { await brewService.updateSelf() }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(brewService.isUpdatingSelf)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(brewService.isCheckingSelfUpdate ? "Checking…" : "Check for Updates…") {
                            checkedUpToDate = false
                            Task {
                                await brewService.checkSelfUpdate()
                                checkedUpToDate = !brewService.selfUpdateAvailable
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(brewService.isCheckingSelfUpdate)
                        if checkedUpToDate {
                            Text("BrewDock is up to date.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 240)
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
