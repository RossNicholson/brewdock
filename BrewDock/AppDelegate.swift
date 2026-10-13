import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var eventMonitor: Any?
    private var dotView: NSView?
    private var cancellables = Set<AnyCancellable>()
    private var updateCheckTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private(set) lazy var hotKey = GlobalHotKey { [weak self] in self?.togglePanel() }
    let brewService = BrewService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: "BrewDock")
            button.action = #selector(togglePanel)
            button.target = self
        }

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

    private func announceUpdates() {
        let outdated = (brewService.casks + brewService.formulae).filter(\.isOutdated).map(\.name)
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
        if !panel.isVisible { openPanel() }
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
        let content = MenuBarView().environmentObject(brewService)
        let hostingView = NSHostingView(rootView: content)
        hostingView.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.resizable, .titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.minSize = NSSize(width: 280, height: 300)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    @objc func togglePanel() {
        if panel.isVisible { closePanel() } else { openPanel() }
    }

    private func openPanel() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        // SwiftUI's onAppear only fires the first time the panel is shown, so
        // refresh here (refresh() skips itself if it ran in the last 30s).
        Task { await brewService.refresh() }
        NotificationCenter.default.post(name: .brewDockPanelOpened, object: nil)

        // Esc closes the panel. A local monitor sees it even while the search
        // field (whose text view would otherwise swallow Esc) has focus.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == UInt16(53), event.window === self.panel else { return event }
            self.closePanel()
            return nil
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    func closePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func positionPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        guard let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        var x = screenRect.midX - panel.frame.width / 2
        let y = screenRect.minY - panel.frame.height

        x = min(max(x, screen.visibleFrame.minX + 4),
                screen.visibleFrame.maxX - panel.frame.width - 4)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowDidResignKey(_ notification: Notification) {
        // Wait a tick for the new key window to settle, then stay open if it's
        // one of ours (a save/open dialog or alert from the Brewfile popover) —
        // closing would tear down the view still waiting on that dialog.
        // Clicking another app leaves us with no key window, so the panel closes.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if NSApp.modalWindow != nil || NSApp.keyWindow != nil { return }
            self.closePanel()
        }
    }
}

extension Notification.Name {
    /// Posted each time the panel opens, so the search field can take focus
    static let brewDockPanelOpened = Notification.Name("BrewDockPanelOpened")
}
