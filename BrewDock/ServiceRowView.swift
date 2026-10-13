import SwiftUI

struct ServiceRowView: View {
    let service: HomebrewService
    @EnvironmentObject var brewService: BrewService
    @State private var isHovered = false

    private var isManaging: Bool {
        brewService.managingServices.contains(service.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            serviceInfo
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .card(hovered: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var statusIcon: some View {
        SymbolTile(symbol: "gearshape.2.fill", fill: service.status.pastel)
    }

    private var serviceInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(service.name)
                .font(.display(16, relativeTo: .headline))
                .textCase(.uppercase)
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
            TagPill(text: service.status.displayLabel, fill: service.status.pastel)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isManaging {
            ProgressView().controlSize(.small)
        } else if isHovered {
            HStack(spacing: 5) {
                switch service.status {
                case .started:
                    actionButton("stop.fill", fill: AppColors.peach, help: "Stop") {
                        Task { await brewService.stopService(service) }
                    }
                    actionButton("arrow.clockwise", fill: AppColors.butter, help: "Restart") {
                        Task { await brewService.restartService(service) }
                    }
                case .stopped, .error, .none:
                    actionButton("play.fill", fill: AppColors.mint, help: "Start") {
                        Task { await brewService.startService(service) }
                    }
                    if service.status == .error {
                        actionButton("arrow.clockwise", fill: AppColors.butter, help: "Restart") {
                            Task { await brewService.restartService(service) }
                        }
                    }
                case .unknown:
                    EmptyView()
                }
            }
            .transition(.opacity)
        }
    }

    private func actionButton(_ symbol: String, fill: Color, help: String, action: @escaping () -> Void) -> some View {
        RoundIconButton(symbol: symbol, fill: fill, foreground: AppColors.ink, help: help, action: action)
    }
}

extension HomebrewService.Status {
    /// Card colour for the status: mint running, peach error, butter unknown, lilac idle
    var pastel: Color {
        switch self {
        case .started: return AppColors.mint
        case .error: return AppColors.peach
        case .unknown: return AppColors.butter
        case .stopped, .none: return AppColors.lilac
        }
    }
}
