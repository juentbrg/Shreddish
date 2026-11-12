import ShreddishCore
import SwiftUI
import UIKit

/// Direction de design « Marché » : papier crème, vert sapin, tomate ; Bricolage Grotesque pour les
/// titres, DM Sans pour le texte (polices OFL embarquées). Variantes sombres pour le mode nuit.
enum Theme {
    // MARK: Couleurs

    static let paper = Color(light: 0xF5F1E8, dark: 0x121713)
    static let card = Color(light: 0xFFFFFF, dark: 0x1E2520)
    static let ink = Color(light: 0x1E2A22, dark: 0xEEF0EA)
    static let muted = Color(light: 0x5D6A61, dark: 0xA3AEA6)
    static let line = Color(light: 0xEFEAE0, dark: 0x2C342E)
    static let green = Color(light: 0x2E6B4A, dark: 0x7FC29B)
    static let onGreen = Color(light: 0xF5F1E8, dark: 0x0F1A13)
    static let greenSoft = Color(light: 0xDCEBDD, dark: 0x22382A)
    static let tomato = Color(light: 0xC8461F, dark: 0xF08A63)
    static let tomatoSoft = Color(light: 0xF7DCD2, dark: 0x45281E)
    static let wheat = Color(light: 0xF3E3C3, dark: 0x40341C)
    static let wheatInk = Color(light: 0x8A5A12, dark: 0xE9C27A)
    static let sky = Color(light: 0xDCE6F0, dark: 0x1F2E3D)

    // MARK: Polices

    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Bricolage Grotesque", size: size, relativeTo: style).weight(weight)
    }

    static func text(_ style: Font.TextStyle = .body, _ weight: Font.Weight = .regular) -> Font {
        .custom("DM Sans", size: UIFont.preferredFont(forTextStyle: style.uiKit).pointSize, relativeTo: style).weight(weight)
    }

    /// Navigation et barre d'onglets aux couleurs et polices du thème.
    @MainActor
    static func applyAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.largeTitleTextAttributes = [
            .font: uiFont("BricolageGrotesque-96ptExtraBold_ExtraBold", size: 34),
        ]
        navigation.titleTextAttributes = [
            .font: uiFont("BricolageGrotesque-96ptExtraBold_Bold", size: 17),
        ]
        UINavigationBar.appearance().standardAppearance = navigation
    }

    /// Instance nommée de la police variable (nom PostScript), repli sur la police système.
    private static func uiFont(_ name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }
}

extension Color {
    /// Couleur claire / sombre depuis deux valeurs hexadécimales.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        )
    }
}

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

// MARK: - Composants

extension View {
    /// Carte blanche arrondie sur fond papier.
    func card(padding: CGFloat = 14, radius: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Liste ou formulaire sur fond papier, lignes en cartes.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paper)
    }

    /// Écran défilant sur fond papier.
    func paperBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}

/// Titre de section dans un écran défilant.
struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.display(20, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.text(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Pastille d'information (durée, coût, kcal).
struct InfoPill: View {
    let text: String
    var background = Theme.card
    var bold = true

    var body: some View {
        Text(text)
            .font(Theme.text(.footnote, bold ? .semibold : .regular))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Bouton plein, arrondi.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(.body, prominent ? .bold : .semibold))
            .foregroundStyle(prominent ? Theme.onGreen : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(prominent ? Theme.green : Theme.card, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension MealType {
    /// Fond et encre de l'icône du repas.
    var tileColors: (background: Color, ink: Color) {
        switch self {
        case .breakfast, .dinner: (Theme.wheat, Theme.wheatInk)
        case .lunch: (Theme.greenSoft, Theme.green)
        case .snack: (Theme.tomatoSoft, Theme.tomato)
        }
    }
}

extension Aisle {
    /// Pastille de couleur du rayon.
    var dotColor: Color {
        switch self {
        case .fruitsLegumes: Color(light: 0xD9A441, dark: 0xE9C27A)
        case .viandePoisson: Theme.tomato
        case .cremerie: Color(light: 0x4E7BA6, dark: 0x8DB4DA)
        case .epicerie: Theme.wheatInk
        case .surgeles: Color(light: 0x3E8FB0, dark: 0x7CC3DE)
        case .boulangerie: Color(light: 0xB07A2E, dark: 0xDDAA62)
        case .autre: Theme.muted
        }
    }
}

/// Icône carrée d'un repas.
struct MealTile: View {
    let type: MealType
    var size: CGFloat = 52

    var body: some View {
        let colors = type.tileColors
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(colors.ink)
            .frame(width: size, height: size)
            .background(colors.background, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}
