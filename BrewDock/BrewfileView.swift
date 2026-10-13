import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BrewfileView: View {
    @EnvironmentObject var brewService: BrewService
    @State private var statusMessage: String? = nil
    @State private var statusIsSuccess = false
    @State private var cleanupPreview: [String] = []
    @State private var showCleanupConfirm = false
    @State private var pendingCleanupPath: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopoverHeader(title: "Brewfile", subtitle: "Back up and restore your Homebrew setup")
                .padding(.bottom, 4)

            Group {
                ColorBlockButton(title: "Export", detail: "Save your installed packages to a Brewfile",
                                 fill: AppColors.mint, symbol: "arrow.up") { exportBrewfile() }
                ColorBlockButton(title: "Install", detail: "Install everything listed in a Brewfile",
                                 fill: AppColors.periwinkle, symbol: "arrow.down") { installFromBrewfile() }
                ColorBlockButton(title: "What's missing?", detail: "See what a Brewfile has that you don't",
                                 fill: AppColors.butter, symbol: "questionmark") { checkBrewfile() }
                ColorBlockButton(title: "Remove unlisted", detail: "Uninstall packages not in a Brewfile",
                                 fill: AppColors.peach, symbol: "trash") { previewCleanup() }
            }
            .disabled(brewService.isBrewfileWorking)
            .opacity(brewService.isBrewfileWorking ? 0.6 : 1)

            if brewService.isBrewfileWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Working…")
                        .font(.mono(10))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(.top, 4)
            }

            if let msg = statusMessage {
                Text(msg)
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(AppColors.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(statusIsSuccess ? AppColors.mint : AppColors.coral,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .popoverChrome()
        .confirmationDialog(
            "Remove \(cleanupPreview.count) package\(cleanupPreview.count == 1 ? "" : "s")?",
            isPresented: $showCleanupConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let path = pendingCleanupPath else { return }
                Task {
                    let (ok, msg) = await brewService.brewfileCleanup(at: path)
                    statusIsSuccess = ok
                    statusMessage = msg
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cleanupPreview.joined(separator: "\n"))
        }
    }

    private func exportBrewfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Brewfile"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = nil
        Task {
            let (ok, msg) = await brewService.brewfileDump(to: url.path)
            statusIsSuccess = ok
            statusMessage = msg
        }
    }

    private func installFromBrewfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .data]
        panel.message = "Choose a Brewfile to install from"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = nil
        Task {
            let (ok, msg) = await brewService.brewfileInstall(from: url.path)
            statusIsSuccess = ok
            statusMessage = msg
        }
    }

    private func checkBrewfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .data]
        panel.message = "Choose a Brewfile to check"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = nil
        Task {
            let (ok, msg) = await brewService.brewfileCheck(at: url.path)
            statusIsSuccess = ok
            statusMessage = msg
        }
    }

    private func previewCleanup() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .data]
        panel.message = "Choose a Brewfile to clean up against"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = nil
        Task {
            let packages = await brewService.brewfileCleanupPreview(at: url.path)
            if packages.isEmpty {
                statusIsSuccess = true
                statusMessage = "Nothing to clean up."
            } else {
                cleanupPreview = packages
                pendingCleanupPath = url.path
                showCleanupConfirm = true
            }
        }
    }
}
