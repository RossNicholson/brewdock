import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var brewService: BrewService
    @State private var searchText = ""
    @State private var selectedTab: Tab = .apps
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingBrewfile = false
    @State private var toastMessage: String? = nil

    init(initialTab: Tab = .apps) {
        _selectedTab = State(initialValue: initialTab)
    }

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
            if showsUpdateBanner {
                updateBanner
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            searchBar
            tabPicker
            contentList
            footer
        }
        .frame(minWidth: 280, minHeight: 300)
        .background(AppColors.ground)
        .animation(.easeInOut(duration: 0.2), value: showsUpdateBanner)
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.mono(10.5, weight: .medium))
                    .foregroundStyle(AppColors.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColors.coral, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 18)
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
                // Longer messages (with brew's reason) stay up long enough to read
                let seconds = min(8, 3 + Double(err.count) / 40)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard brewService.lastError == err else { return }
                withAnimation(.easeOut) { toastMessage = nil }
                brewService.lastError = nil
            }
        }
    }

    // MARK: Header

    private var dragHandle: some View {
        Capsule()
            .fill(AppColors.secondaryText.opacity(0.35))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
            .help("Drag to move · Resize from edges or corners")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("BrewDock")
                    .font(.display(32, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Homebrew in your menu bar")
                    .font(.mono(10))
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 8)
            refreshButton
            brewfileButton
            settingsButton
            infoButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var showsUpdateBanner: Bool {
        outdatedCount > 0 && (selectedTab == .apps || selectedTab == .tools)
    }

    /// Peach colour block offering to update everything, like the big call-to-action
    /// card on the Don't Worry home screen
    private var updateBanner: some View {
        let busy = !brewService.updatingPackages.isEmpty
        return HStack(spacing: 10) {
            Text("\(outdatedCount)")
                .font(.display(34, relativeTo: .largeTitle))
                .foregroundStyle(AppColors.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(outdatedCount == 1 ? "Update ready" : "Updates ready")
                    .font(.display(18, relativeTo: .headline))
                    .textCase(.uppercase)
                Text(busy ? (brewService.progress[BrewService.allUpdatesKey] ?? "Updating…") : "Update everything in one go")
                    .lineLimit(1)
                    .font(.mono(9.5))
                    .opacity(0.75)
            }
            .foregroundStyle(AppColors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30, height: 30)
            } else {
                RoundIconButton(symbol: "arrow.up", size: 30, fill: AppColors.ink, foreground: .white, help: "Update all") {
                    Task { await brewService.upgradeAll() }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(AppColors.peach, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Search & tabs

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.mono(11.5))
                .foregroundStyle(AppColors.text)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
    }

    private var searchPlaceholder: String {
        switch selectedTab {
        case .services: return "Search services…"
        case .discover: return "Search all of Homebrew…"
        default:        return "Search packages…"
        }
    }

    /// Pill switcher: the selected tab is a solid ink capsule, like the period picker
    /// on the Don't Worry insights screen
    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let selected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                        searchText = ""
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.mono(10.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? AppColors.onSolid : AppColors.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if selected { Capsule().fill(AppColors.solid) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppColors.surface, in: Capsule())
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Lists

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
                CardList {
                    sectionTitle(selectedTab == .apps ? "Your apps" : "Your tools", count: packages.count)
                    ForEach(packages) { package in
                        PackageRowView(package: package)
                            .environmentObject(brewService)
                    }
                }
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
                CardList {
                    let running = brewService.services.filter { $0.status == .started }.count
                    sectionTitle("Services", count: filteredServices.count, detail: "\(running) running")
                    ForEach(filteredServices) { service in
                        ServiceRowView(service: service)
                            .environmentObject(brewService)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.display(17, relativeTo: .headline))
                .textCase(.uppercase)
                .foregroundStyle(AppColors.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(detail ?? "\(count)")
                .font(.mono(10))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private func loadingView(label: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.mono(10.5))
                .foregroundStyle(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            SymbolTile(symbol: searchText.isEmpty ? "tray" : "magnifyingglass",
                       fill: AppColors.lilac, size: 40)
                .padding(.bottom, 4)
            Text(searchText.isEmpty ? "Nothing here yet" : "No matches")
                .font(.display(20, relativeTo: .title3))
                .textCase(.uppercase)
                .foregroundStyle(AppColors.text)
            Text(searchText.isEmpty ? emptyHint : "Nothing matches \"\(searchText)\"")
                .font(.mono(10))
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: String {
        switch selectedTab {
        case .services: return "No Homebrew services installed"
        default: return "Find something to install in Discover"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Group {
                switch selectedTab {
                case .services:
                    let running = brewService.services.filter { $0.status == .started }.count
                    Text("\(brewService.services.count) services · \(running) running")
                case .discover:
                    Text("\(DiscoverCatalog.all.count) packages to discover")
                default:
                    Text("\(brewService.casks.count) apps · \(brewService.formulae.count) tools")
                }
            }
            .font(.mono(9.5))
            .foregroundStyle(AppColors.secondaryText)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.mono(9.5, weight: .semibold))
                .textCase(.uppercase)
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColors.hairline).frame(height: 1)
        }
    }

    // MARK: Header buttons

    private var refreshButton: some View {
        let busy = selectedTab == .services ? brewService.isLoadingServices : brewService.isLoading
        return HeaderIconButton(symbol: "arrow.clockwise", help: "Refresh") {
            if selectedTab == .services {
                Task { await brewService.refreshServices() }
            } else {
                Task { await brewService.refresh(force: true) }
            }
        }
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }

    private var brewfileButton: some View {
        HeaderIconButton(symbol: "doc.text", help: "Brewfile backup & restore") {
            showingBrewfile.toggle()
        }
        .popover(isPresented: $showingBrewfile, arrowEdge: .bottom) {
            BrewfileView().environmentObject(brewService)
        }
    }

    private var settingsButton: some View {
        HeaderIconButton(symbol: "gearshape", help: "Settings") {
            showingSettings.toggle()
        }
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsView().environmentObject(brewService)
        }
    }

    private var infoButton: some View {
        HeaderIconButton(symbol: "info", help: "About & help") {
            showingAbout.toggle()
        }
        .popover(isPresented: $showingAbout, arrowEdge: .bottom) {
            aboutView
        }
    }

    // MARK: About & help

    private var aboutView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                PopoverHeader(
                    title: "BrewDock",
                    subtitle: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")\nMade by Ross Nicholson"
                )
                SymbolTile(symbol: "mug.fill", fill: AppColors.butter, size: 40)
            }

            ColorBlockButton(title: "Get help", detail: "Bugs, questions and feature requests", fill: AppColors.mint) {
                NSWorkspace.shared.open(URL(string: "https://rossnicholson.dev/support")!)
            }
            ColorBlockButton(title: "Email support", detail: "support@rossnicholson.dev", fill: AppColors.periwinkle, symbol: "envelope.fill") {
                NSWorkspace.shared.open(URL(string: "mailto:support@rossnicholson.dev")!)
            }
            ColorBlockButton(title: "Buy me a coffee", detail: "If BrewDock saves you time", fill: AppColors.peach, symbol: "cup.and.saucer.fill") {
                NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/rossnicholson")!)
            }

            HStack(spacing: 10) {
                MonoLink(title: "Website", destination: URL(string: "https://rossnicholson.dev")!)
                MonoLink(title: "GitHub", destination: URL(string: "https://github.com/RossNicholson/brewdock")!)
                MonoLink(title: "Terms", destination: URL(string: "https://rossnicholson.dev/terms")!)
                MonoLink(title: "Privacy", destination: URL(string: "https://rossnicholson.dev/privacy")!)
            }
            .padding(.top, 2)
        }
        .popoverChrome()
    }
}

private extension Array where Element == BrewPackage {
    func filtered(by query: String) -> [BrewPackage] {
        guard !query.isEmpty else { return self }
        return filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

/// Scrolling stack of card rows, lined up with the search bar above it
struct CardList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }
}
