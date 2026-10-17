import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The panel opens at this size and can be dragged bigger, but not smaller
    static let panelDefaultSize = NSSize(width: 380, height: 520)
    static let panelMinimumSize = NSSize(width: 330, height: 300)

    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanelController!
    private var dotView: NSView?
    private var cancellables = Set<AnyCancellable>()
    private var updateCheckTask: Task<Void, Never>?
    private var autoUpdateTask: Task<Void, Never>?
    private var isAutoUpdating = false
    private(set) lazy var hotKey = GlobalHotKey { [weak self] in self?.panel.toggle() }
    let brewService = BrewService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: "BrewDock")

        setupPanel()
        setupUpdateDot()
        observeUpdates()
        hotKey.update()

        // Don't shell out to brew when the app is launched as a unit-test host.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        UNUserNotificationCenter.current().delegate = self
        Task {
            await brewService.checkSelfUpdateSilent()
            // Load packages at launch too, so the menu bar dot shows outdated
            // packages before the panel is ever opened.
            await brewService.refresh()
            announceUpdates()
        }
        startPeriodicUpdateCheck()
        startAutoUpdate()
    }

    /// A menu bar app can run for days, so the launch-time check isn't enough.
    /// Every 6 hours, fetch Homebrew's latest package index (`brew update`) and
    /// refresh, so the dot (and optional notification) reflect new versions of
    /// everything installed, not just BrewDock.
    private func startPeriodicUpdateCheck() {
        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
                guard let self else { return }
                await self.brewService.checkSelfUpdate(showProgress: false)
                await self.brewService.refresh(force: true)
                self.announceUpdates()
            }
        }
    }

    /// Auto-update (off unless turned on in Settings): every 10 minutes, update
    /// all apps and tools. The loop always runs and checks the setting each time,
    /// so turning it on or off takes effect without a restart.
    private func startAutoUpdate() {
        autoUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(BrewService.autoUpdateInterval))
                guard let self else { return }
                if UserDefaults.standard.bool(forKey: BrewService.autoUpdateKey) {
                    await self.runAutoUpdate()
                }
            }
        }
    }

    /// One Auto-update run, also started straight away when the setting is turned on
    func runAutoUpdate() async {
        guard !isAutoUpdating else { return }
        isAutoUpdating = true
        defer { isAutoUpdating = false }
        let updated = await brewService.autoUpdate()
        await UpdateNotifier.notifyAutoUpdated(updated)
        announceUpdates()
        // Updating BrewDock restarts it, so not while the panel is in use;
        // the next run picks it up.
        if brewService.selfUpdateAvailable, !panel.isVisible, !brewService.isBusy,
           UserDefaults.standard.bool(forKey: BrewService.autoUpdateKey) {
            await brewService.updateSelf()
        }
    }

    private func announceUpdates() {
        // Apps and the tools you installed first, dependencies last
        let packages = brewService.casks + brewService.formulae.filter { !$0.isDependency }
            + brewService.formulae.filter(\.isDependency)
        let outdated = packages.filter(\.isOutdated).map(\.name)
        UpdateNotifier.notifyIfNew(outdated: outdated)
    }

    // Clicking the notification opens the panel
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.showPanel() }
    }

    // Show the banner even though BrewDock counts as the active app
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func showPanel() {
        panel.open()
    }

    func closePanel() {
        panel.close()
    }

    private func setupUpdateDot() {
        guard let button = statusItem.button else { return }
        let size: CGFloat = 7
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.orange.cgColor
        dot.layer?.cornerRadius = size / 2
        dot.isHidden = true
        button.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: size),
            dot.heightAnchor.constraint(equalToConstant: size),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
        ])
        dotView = dot
    }

    private func observeUpdates() {
        Publishers.CombineLatest3(brewService.$casks, brewService.$formulae, brewService.$selfUpdateAvailable)
            .receive(on: RunLoop.main)
            .sink { [weak self] casks, formulae, selfUpdate in
                let hasUpdates = (casks + formulae).contains(where: \.isOutdated) || selfUpdate
                self?.dotView?.isHidden = !hasUpdates
            }
            .store(in: &cancellables)
    }

    private func setupPanel() {
        panel = MenuBarPanelController(statusItem: statusItem)
        panel.setContent(defaultSize: Self.panelDefaultSize, minimumSize: Self.panelMinimumSize) {
            MenuBarView().environmentObject(brewService)
        }
        panel.onOpen = { [weak self] in
            // SwiftUI's onAppear only fires the first time the panel is shown, so
            // refresh here (refresh() skips itself if it ran in the last 30s).
            Task { await self?.brewService.refresh() }
            NotificationCenter.default.post(name: .brewDockPanelOpened, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted each time the panel opens, so the search field can take focus
    static let brewDockPanelOpened = Notification.Name("BrewDockPanelOpened")
}
