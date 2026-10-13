import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var brewService: BrewService
    @State private var searchText = ""
    @State private var selectedTab: Tab = .apps
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingHelp = false
    @State private var showingBrewfile = false
    @State private var toastMessage: String? = nil

    enum Tab: String, CaseIterable {
        case apps     = "Apps"
        case tools    = "Tools"
        case services = "Services"
        case discover = "Discover"
    }

    var outdatedCount: Int {
        brewService.casks.filter(\.isOutdated).count +
        brewService.formulae.filter(\.isOutdated).count
    }

    var filteredCasks: [BrewPackage] {
        brewService.casks.filtered(by: searchText)
    }

    var filteredFormulae: [BrewPackage] {
        brewService.formulae.filtered(by: searchText)
    }

    var filteredServices: [HomebrewService] {
        guard !searchText.isEmpty else { return brewService.services }
        return brewService.services.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            header
            Divider().opacity(dividerOpacity)
            searchBar
            Divider().opacity(dividerOpacity)
            tabPicker
            Divider().opacity(dividerOpacity)
            contentList
            Divider().opacity(dividerOpacity)
            footer
        }
        .frame(minWidth: 280, minHeight: 300)
        .liquidGlassBackground(in: Rectangle())
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.88))
                    .clipShape(Capsule())
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .services && brewService.services.isEmpty {
                Task { await brewService.refreshServices() }
            }
        }
        .onChange(of: brewService.lastError) { err in
            guard let err else { return }
            withAnimation(.spring(duration: 0.3)) { toastMessage = err }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeOut) { toastMessage = nil }
                brewService.lastError = nil
            }
        }
    }

    private var dividerOpacity: Double {
        if #available(macOS 26, *) { return 0.25 }
        return 1.0
    }

    private var dragHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
            Spacer()
        }
        .frame(height: 22)
        .help("Drag to move · Resize from edges or corners")
    }

    private var header: some View {
        HStack {
            Image(systemName: "mug.fill")
                .foregroundStyle(.brown)
                .font(.title3)
            Text("BrewDock")
                .font(.headline)
            Spacer()
            if outdatedCount > 0 {
                Button {
                    Task { await brewService.upgradeAll() }
                } label: {
                    Label("Update \(outdatedCount)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .liquidGlassInteractive(in: Capsule())
            }
            brewfileButton
            helpButton
            infoButton
            settingsButton
            refreshButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.footnote)
            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlassInteractive(in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var searchPlaceholder: String {
        switch selectedTab {
        case .services: return "Search services…"
        case .discover: return "Search \(DiscoverCatalog.all.count) packages…"
        default:        return "Search packages…"
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                        searchText = ""
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var contentList: some View {
        Group {
            switch selectedTab {
            case .apps, .tools:
                packagesContent
            case .services:
                servicesContent
            case .discover:
                DiscoverTabView(searchText: $searchText)
                    .environmentObject(brewService)
            }
        }
        .frame(minHeight: 80, maxHeight: .infinity)
    }

    private var packagesContent: some View {
        let packages = selectedTab == .apps ? filteredCasks : filteredFormulae
        return Group {
            // Only the first load shows a spinner; later refreshes (e.g. after an
            // install) update the list in place instead of blanking it.
            if brewService.isLoading && brewService.casks.isEmpty && brewService.formulae.isEmpty {
                loadingView(label: "Loading packages…")
            } else if packages.isEmpty {
                emptyView
            } else {
                List(packages) { package in
                    PackageRowView(package: package)
                        .environmentObject(brewService)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var servicesContent: some View {
        Group {
            if brewService.isLoadingServices {
                loadingView(label: "Loading services…")
            } else if filteredServices.isEmpty {
                emptyView
            } else {
                List(filteredServices) { service in
                    ServiceRowView(service: service)
                        .environmentObject(brewService)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func loadingView(label: String) -> some View {
        VStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No packages installed" : "No results for \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            Group {
                switch selectedTab {
                case .services:
                    let running = brewService.services.filter { $0.status == .started }.count
                    Text("\(brewService.services.count) services · \(running) running")
                case .discover:
                    Text("\(DiscoverCatalog.all.count) packages available")
                default:
                    Text("\(brewService.casks.count) apps · \(brewService.formulae.count) tools")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsButton: some View {
        Button {
            showingSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.footnote)
                .padding(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .liquidGlassInteractive(in: Circle())
        .popover(isPresented: $showingSettings, arrowEdge: .top) {
            SettingsView()
        }
    }

    private var refreshButton: some View {
        Button {
            if selectedTab == .services {
                Task { await brewService.refreshServices() }
            } else {
                Task { await brewService.refresh(force: true) }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.footnote)
                .padding(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .liquidGlassInteractive(in: Circle())
        .disabled(selectedTab == .services ? brewService.isLoadingServices : brewService.isLoading)
    }

    private var brewfileButton: some View {
        Button { showingBrewfile.toggle() } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.footnote)
                .padding(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .liquidGlassInteractive(in: Circle())
        .popover(isPresented: $showingBrewfile, arrowEdge: .top) {
            BrewfileView().environmentObject(brewService)
        }
    }

    private var helpButton: some View {
        Button { showingHelp.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.footnote)
                .padding(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .liquidGlassInteractive(in: Circle())
        .popover(isPresented: $showingHelp, arrowEdge: .top) {
            helpView
        }
    }

    private var helpView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "lifepreserver")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text("Help & Support")
                    .font(.title3).fontWeight(.semibold)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Found a bug or need help? Visit the support page or drop us an email — we read everything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Feature requests and feedback are always welcome too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Link(destination: URL(string: "https://rossnicholson.dev/support")!) {
                    Label("Support Page", systemImage: "globe")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .liquidGlassInteractive(in: Capsule())

                Link(destination: URL(string: "mailto:support@rossnicholson.dev")!) {
                    Label("support@rossnicholson.dev", systemImage: "envelope")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .liquidGlassInteractive(in: Capsule())
            }
        }
        .padding(20)
        .frame(width: 240)
    }

    private var infoButton: some View {
        Button { showingAbout.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .padding(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .liquidGlassInteractive(in: Circle())
        .popover(isPresented: $showingAbout, arrowEdge: .top) {
            aboutView
        }
    }

    private var aboutView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "mug.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.brown)
                Text("BrewDock")
                    .font(.title3).fontWeight(.semibold)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                Text("Made by Ross Nicholson")
                    .font(.subheadline)
                Link("rossnicholson.dev", destination: URL(string: "https://rossnicholson.dev")!)
                    .font(.caption)
                Link(destination: URL(string: "https://github.com/RossNicholson/brewdock")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                }
            }

            Divider()

            VStack(spacing: 4) {
                Text("If you find BrewDock helpful:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://buymeacoffee.com/rossnicholson")!) {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .liquidGlassInteractive(in: Capsule())
            }

            Divider()

            HStack(spacing: 12) {
                Link("Terms & Conditions", destination: URL(string: "https://rossnicholson.dev/terms")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Privacy Policy", destination: URL(string: "https://rossnicholson.dev/privacy")!)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 220)
    }
}

private extension Array where Element == BrewPackage {
    func filtered(by query: String) -> [BrewPackage] {
        guard !query.isEmpty else { return self }
        return filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
