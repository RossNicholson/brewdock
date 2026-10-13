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
            Divider()
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
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentIndex > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .disabled(currentIndex == 0)

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
                    .padding(.vertical, 7)
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
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentIndex < allCategories.count - 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .disabled(currentIndex == allCategories.count - 1)
        }
    }

    private func pill(_ category: DiscoverPackage.Category?, label: String, symbol: String) -> some View {
        let selected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = category }
        } label: {
            Label(label, systemImage: symbol)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var packageList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No results for \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                List(filtered) { package in
                    DiscoverPackageRow(package: package)
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
                HStack(spacing: 5) {
                    Text(package.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(package.type == .cask ? "app" : "tool")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
                Text(package.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            actionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var packageIcon: some View {
        if let appIcon = installedBrewPackage?.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let urlString = package.iconURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                default:
                    sfSymbolIcon
                }
            }
            .frame(width: 28, height: 28)
        } else {
            sfSymbolIcon
        }
    }

    private var sfSymbolIcon: some View {
        Image(systemName: package.icon.symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(package.icon.color)
            .frame(width: 28, height: 28)
            .background(package.icon.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInstalling {
            ProgressView().scaleEffect(0.6).frame(width: 60)
        } else if isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.body)
        } else {
            Button("Install") {
                Task { await brewService.install(package) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
    }
}
