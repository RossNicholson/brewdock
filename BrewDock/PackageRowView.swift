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
            Spacer()
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { launch() }
        .alert("Quit \(package.name)?", isPresented: $showingUninstallAlert) {
            Button("Quit & Uninstall", role: .destructive) {
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
            Text("\(package.name) is currently running. It needs to quit before it can be uninstalled.")
        }
    }

    private var packageIcon: some View {
        Group {
            if let appIcon = package.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let sfIcon = package.formulaIcon {
                Image(systemName: sfIcon.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(sfIcon.color)
                    .frame(width: 28, height: 28)
                    .background(sfIcon.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var packageInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(package.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if package.isOutdated {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Text(package.version)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isUpdating || isRemoving {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
        } else if isHovered {
            HStack(spacing: 8) {
                Button("Open") { launch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                if package.isOutdated {
                    Button {
                        Task { await brewService.upgrade(package) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .help("Update")
                }
                Button {
                    if package.runningApplication != nil {
                        showingUninstallAlert = true
                    } else {
                        Task { await brewService.uninstall(package) }
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Uninstall")
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
