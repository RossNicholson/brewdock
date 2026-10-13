import SwiftUI

struct DiscoverTabView: View {
    @Binding var searchText: String
    @EnvironmentObject var brewService: BrewService
    @State private var selectedCategory: DiscoverPackage.Category? = nil

    var filtered: [DiscoverPackage] {
        var list = selectedCategory.map { cat in
            DiscoverCatalog.all.filter { $0.category == cat }
        } ?? DiscoverCatalog.all
        if !searchText.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryPicker
                .padding(.horizontal, 8)
            packageList
        }
    }

    // Ordered list of all categories including "All" (nil)
    private var allCategories: [DiscoverPackage.Category?] {
        [nil] + DiscoverPackage.Category.allCases.map { Optional($0) }
    }

    private var currentIndex: Int {
        allCategories.firstIndex(where: { $0 == selectedCategory }) ?? 0
    }

    private func navigateCategory(by delta: Int) {
        let next = currentIndex + delta
        guard next >= 0 && next < allCategories.count else { return }
        withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = allCategories[next] }
    }

    private var categoryPicker: some View {
        HStack(spacing: 0) {
            // Left chevron
            Button { navigateCategory(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.text)
            .opacity(currentIndex > 0 ? 1 : 0.3)
            .disabled(currentIndex == 0)
            .accessibilityLabel("Previous category")

            // Pill strip — scrolls to follow the selected pill
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        pill(nil, label: "All", symbol: "square.grid.2x2")
                            .id("all")
                        ForEach(DiscoverPackage.Category.allCases, id: \.self) { cat in
                            pill(cat, label: cat.rawValue, symbol: cat.symbol)
                                .id(cat)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedCategory) { cat in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let cat {
                            proxy.scrollTo(cat, anchor: .center)
                        } else {
                            proxy.scrollTo("all", anchor: .center)
                        }
                    }
                }
            }
            .mask(
                // Fade edges to hint there's more to scroll
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12)
                }
            )

            // Right chevron
            Button { navigateCategory(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.text)
            .opacity(currentIndex < allCategories.count - 1 ? 1 : 0.3)
            .disabled(currentIndex == allCategories.count - 1)
            .accessibilityLabel("Next category")
        }
    }

    private func pill(_ category: DiscoverPackage.Category?, label: String, symbol: String) -> some View {
        let selected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = category }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.mono(10, weight: selected ? .semibold : .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? AppColors.onSolid : AppColors.text)
            .background(selected ? AppColors.solid : AppColors.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var packageList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 6) {
                    SymbolTile(symbol: "magnifyingglass", fill: AppColors.lilac, size: 40)
                        .padding(.bottom, 4)
                    Text("No matches")
                        .font(.display(20, relativeTo: .title3))
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.text)
                    Text("Nothing matches \"\(searchText)\"")
                        .font(.mono(10))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CardList {
                    ForEach(filtered) { package in
                        DiscoverPackageRow(package: package)
                            .environmentObject(brewService)
                    }
                }
            }
        }
    }
}

struct DiscoverPackageRow: View {
    let package: DiscoverPackage
    @EnvironmentObject var brewService: BrewService

    var isInstalled: Bool {
        installedBrewPackage != nil
    }

    var isInstalling: Bool {
        brewService.installingPackages.contains(package.id)
    }

    private var installedBrewPackage: BrewPackage? {
        switch package.type {
        case .cask:    return brewService.casks.first    { package.matches(installedName: $0.name) }
        case .formula: return brewService.formulae.first { package.matches(installedName: $0.name) }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            packageIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.displayName)
                        .font(.display(16, relativeTo: .headline))
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    TagPill(text: package.type == .cask ? "app" : "tool",
                            fill: package.type == .cask ? AppColors.periwinkle : AppColors.mint)
                }
                Text(package.description)
                    .font(.mono(9.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            actionButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .card()
    }

    @ViewBuilder
    private var packageIcon: some View {
        if let appIcon = installedBrewPackage?.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 30, height: 30)
        } else if let urlString = package.iconURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                default:
                    sfSymbolIcon
                }
            }
            .frame(width: 30, height: 30)
        } else {
            sfSymbolIcon
        }
    }

    private var sfSymbolIcon: some View {
        SymbolTile(symbol: package.icon.symbol, fill: AppColors.pastel(for: package.id))
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInstalling {
            ProgressView().controlSize(.small)
        } else if isInstalled {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.ink)
                .frame(width: 26, height: 26)
                .background(AppColors.mint, in: Circle())
                .help("Installed")
                .accessibilityLabel("Installed")
        } else {
            RoundIconButton(symbol: "plus", help: "Install \(package.displayName)") {
                Task { await brewService.install(package) }
            }
        }
    }
}
