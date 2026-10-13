import SwiftUI
import AppKit
import CoreText

// The same look as the Don't Worry and Word Slip apps: pastel colour blocks,
// bold condensed uppercase titles and small monospaced labels.

enum AppColors {
    // Pastels. Text on them is always `ink`, in light and dark mode.
    static let peach = Color(hex: 0xF6C3B4)
    static let butter = Color(hex: 0xF6E2A4)
    static let periwinkle = Color(hex: 0xC3C7F6)
    static let mint = Color(hex: 0xC2E6D6)
    static let lilac = Color(hex: 0xDCD2F0)
    static let coral = Color(hex: 0xEE9C86)
    static let ink = Color(hex: 0x232428)

    static let pastels = [peach, butter, periwinkle, mint, lilac]

    static let ground = Color(light: 0xE9EFEA, dark: 0x16171A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2B30)
    static let surfaceHover = Color(light: 0xF6F8F6, dark: 0x33353B)
    static let text = Color(light: 0x232428, dark: 0xF2F1EE)
    static let secondaryText = Color(light: 0x5E636C, dark: 0xA9ADB5)
    static let hairline = Color(light: 0xD5DCD7, dark: 0x2E3035)

    /// Round buttons and the selected tab: ink on light, cream on dark
    static let solid = Color(light: 0x232428, dark: 0xF2F1EE)
    static let onSolid = Color(light: 0xFFFFFF, dark: 0x232428)

    static let toggle = Color(hex: 0x4FAE87)
    static let destructive = Color(light: 0xB93A26, dark: 0xF19A85)

    /// A stable pastel for a package name, so each one keeps its colour
    static func pastel(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return pastels[sum % pastels.count]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A colour that switches with light and dark mode
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Fonts

/// The bundled fonts: Barlow Condensed for titles and Geist Mono for labels.
enum AppFonts {
    static let display = "BarlowCondensed-Bold"

    enum MonoWeight {
        case regular, medium, semibold

        var fontName: String {
            switch self {
            case .regular: return "GeistMono-Regular"
            case .medium: return "GeistMono-Medium"
            case .semibold: return "GeistMono-SemiBold"
            }
        }
    }

    // Registered on first use, so previews get the fonts too
    static let registered: Void = {
        for name in ["BarlowCondensed-Bold", "GeistMono-Regular", "GeistMono-Medium", "GeistMono-SemiBold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

extension Font {
    /// Bold condensed titles. Use with `.textCase(.uppercase)`.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        _ = AppFonts.registered
        return .custom(AppFonts.display, size: size, relativeTo: style)
    }

    /// Small monospaced labels and supporting text
    static func mono(_ size: CGFloat, weight: AppFonts.MonoWeight = .regular, relativeTo style: Font.TextStyle = .footnote) -> Font {
        _ = AppFonts.registered
        return .custom(weight.fontName, size: size, relativeTo: style)
    }
}

// MARK: - Components

/// A filled circle with a symbol: the round arrow/plus buttons from the other apps
struct RoundIconButton: View {
    let symbol: String
    var size: CGFloat = 26
    var fill: Color = AppColors.solid
    var foreground: Color = AppColors.onSolid
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help ?? "")
        .accessibilityLabel(help ?? symbol)
    }
}

/// An outlined circle for the header's secondary actions
struct HeaderIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .frame(width: 26, height: 26)
                .background(AppColors.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Small uppercase mono label in a capsule, e.g. "UPDATE" or "RUNNING"
struct TagPill: View {
    let text: String
    var fill: Color = AppColors.butter
    var foreground: Color = AppColors.ink

    var body: some View {
        Text(text)
            .font(.mono(9, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }
}

/// A rounded square with a symbol on a pastel, like the category icons in Don't Worry
struct SymbolTile: View {
    let symbol: String
    let fill: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(AppColors.ink)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Large condensed title with a mono subtitle, used at the top of every popover
struct PopoverHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.display(30, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .foregroundStyle(AppColors.text)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.mono(10.5))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A pastel block with a condensed title, a mono description and a round arrow,
/// like the "Share what's on your mind" card
struct ColorBlockButton: View {
    let title: String
    let detail: String
    let fill: Color
    var symbol: String = "arrow.up.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.display(18, relativeTo: .headline))
                        .textCase(.uppercase)
                    Text(detail)
                        .font(.mono(9.5))
                        .opacity(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(AppColors.ink, in: Circle())
            }
            .foregroundStyle(AppColors.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Text link styled as a mono label
struct MonoLink: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .font(.mono(10.5, weight: .medium))
                .foregroundStyle(AppColors.text)
                .underline()
        }
        .buttonStyle(.plain)
    }
}

/// Slight shrink while pressed, so plain buttons still feel tappable
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// White (or dark) rounded card used for every list row
    func card(hovered: Bool = false) -> some View {
        background(hovered ? AppColors.surfaceHover : AppColors.surface,
                   in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Popover body: padded, on the app's ground colour
    func popoverChrome(width: CGFloat = 260) -> some View {
        padding(18)
            .frame(width: width)
            .background(AppColors.ground)
    }
}
