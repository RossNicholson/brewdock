import SwiftUI
import AppKit

struct PackageRowView: View {
    let package: BrewPackage
    @EnvironmentObject var brewService: BrewService
    @State private var isHovered = false
    @State private var showingUninstallAlert = false

    private var isUpdating: Bool {
        brewService.updatingPackages.contains(package.name)
    }

    private var isRemoving: Bool {
        brewService.removingPackages.contains(package.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            packageIcon
            packageInfo
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .card(hovered: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { launch() }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .alert("Uninstall \(package.name)?", isPresented: $showingUninstallAlert) {
            Button(package.runningApplication != nil && !package.isBrewDock ? "Quit & Uninstall" : "Uninstall", role: .destructive) {
                // BrewDock uninstalling itself: the service hands off to a detached
                // helper and quits, so don't terminate ourselves first.
                let app = package.isBrewDock ? nil : package.runningApplication
                app?.terminate()
                Task {
                    if app != nil {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                    }
                    await brewService.uninstall(package)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(uninstallMessage)
        }
    }

    private var uninstallMessage: String {
        if package.isBrewDock {
            return "BrewDock will quit and remove itself."
        }
        if package.runningApplication != nil {
            return "\(package.name) is running. It will be quit first, then removed from your Mac."
        }
        return "This removes \(package.name) from your Mac."
    }

    private var packageIcon: some View {
        Group {
            if let appIcon = package.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 30, height: 30)
            } else {
                SymbolTile(symbol: package.formulaIcon?.symbol ?? "shippingbox.fill",
                           fill: AppColors.pastel(for: package.name))
            }
        }
    }

    private var packageInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(package.name)
                    .font(.display(16, relativeTo: .headline))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                if package.isOutdated {
                    TagPill(text: "Update")
                }
            }
            Text(package.version)
                .font(.mono(9.5))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isUpdating || isRemoving {
            HStack(spacing: 6) {
                Text(isUpdating ? "Updating" : "Removing")
                    .font(.mono(9.5))
                    .foregroundStyle(AppColors.secondaryText)
                ProgressView().controlSize(.small)
            }
        } else if isHovered {
            HStack(spacing: 5) {
                if package.isOutdated {
                    RoundIconButton(symbol: "arrow.up", fill: AppColors.butter, foreground: AppColors.ink, help: "Update") {
                        Task { await brewService.upgrade(package) }
                    }
                }
                RoundIconButton(symbol: "trash", fill: AppColors.peach, foreground: AppColors.ink, help: "Uninstall") {
                    showingUninstallAlert = true
                }
                RoundIconButton(symbol: "arrow.up.right", help: package.type == .formula || package.isCLIOnly ? "Open in Terminal" : "Open") {
                    launch()
                }
            }
            .transition(.opacity)
        }
    }

    private func launch() {
        switch package.type {
        case .cask:
            if let url = package.appURL {
                NSWorkspace.shared.open(url)
            } else {
                // CLI-only cask (e.g. claude-code) — open in terminal like a formula
                openInTerminal(command: package.name)
            }
        case .formula:
            openInTerminal(command: package.name)
        }
        (NSApp.delegate as? AppDelegate)?.closePanel()
    }

    private static let iterm2URL: URL? =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")

    private func openInTerminal(command: String) {
        // Strip anything that isn't a safe filename character so the package name
        // can't influence the path (e.g. a '/' escaping the temp directory).
        let safeName = String(command.unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0)
        })
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brewdock-\(safeName)-\(UUID().uuidString.prefix(8)).command")
        // Single-quote the command to handle names with hyphens, dots, @ etc.
        let safe = command.replacingOccurrences(of: "'", with: "'\\''")
        // Library formulae (openssl@3, libpng…) have no command of their own, so
        // show `brew info` for them instead of "command not found".
        let script = """
        #!/bin/bash
        clear
        if command -v '\(safe)' >/dev/null 2>&1; then
            '\(safe)'
        else
            '\(brewPath)' info '\(safe)'
        fi

        """
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: tmp.path
            )
            if let iterm2 = Self.iterm2URL {
                NSWorkspace.shared.open(
                    [tmp], withApplicationAt: iterm2,
                    configuration: .init(), completionHandler: nil
                )
            } else {
                NSWorkspace.shared.open(tmp)
            }
            // Generous delay: a cold-launching terminal may not read the file for a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: tmp)
            }
        } catch {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }
}
