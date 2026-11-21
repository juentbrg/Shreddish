import ShreddishCore
import SwiftUI
import UIKit

/// Direction de design « Marché » : papier crème, vert sapin, tomate ; Bricolage Grotesque pour les
/// titres, DM Sans pour le texte (polices OFL embarquées). Variantes sombres pour le mode nuit.
enum Theme {
    // MARK: Couleurs

    static let paper = Color(light: 0xF5F1E8, dark: 0x131514)
    static let card = Color(light: 0xFFFFFF, dark: 0x1F2220)
    static let ink = Color(light: 0x1E2A22, dark: 0xEFEEEA)
    static let muted = Color(light: 0x4F5B53, dark: 0xAEB2AE)
    static let line = Color(light: 0xEFEAE0, dark: 0x2C2F2D)
    static let tomato = Color(light: 0xC8461F, dark: 0xF08A63)
    static let tomatoSoft = Color(light: 0xF7DCD2, dark: 0x45281E)
    /// Texte d'alerte sur fond `tomatoSoft` : contraste AA (spec 017, FR-1713).
    static let tomatoInk = Color(light: 0x9A3214, dark: 0xF7B094)
    static let wheat = Color(light: 0xF3E3C3, dark: 0x40341C)
    static let wheatInk = Color(light: 0x8A5A12, dark: 0xE9C27A)
    static let sky = Color(light: 0xDCE6F0, dark: 0x1F2E3D)

    // « Couleurs du marché » : tomate en couleur de marque (sélection, actions), vert réservé au
    // « réussi / dans la cible », une teinte par macro et par moment du repas.
    static let accent = Color(light: 0xB9471F, dark: 0xF08A63)
    static let onAccent = Color(light: 0xFFF8F0, dark: 0x1E0F08)
    static let success = Color(light: 0x1D5536, dark: 0x8ED1A8)
    static let successSoft = Color(light: 0xDDEFE2, dark: 0x22382A)
    static let protein = MacroPalette(
        soft: Color(light: 0xFBE3D9, dark: 0x3A2420), ink: Color(light: 0x8E2E12, dark: 0xF7B094),
        bar: Color(light: 0xD9532B, dark: 0xF08A63)
    )
    static let carbs = MacroPalette(
        soft: Color(light: 0xFCEFCF, dark: 0x3A3020), ink: Color(light: 0x7A5205, dark: 0xE9C27A),
        bar: Color(light: 0xE0A021, dark: 0xE9C27A)
    )
    static let fat = MacroPalette(
        soft: Color(light: 0xDEE8F5, dark: 0x1F2E3D), ink: Color(light: 0x234C7E, dark: 0xA9C9F2),
        bar: Color(light: 0x4A7FC1, dark: 0x8FB8EC)
    )
    static let plum = MacroPalette(
        soft: Color(light: 0xEBE3F6, dark: 0x2E2540), ink: Color(light: 0x5B3E86, dark: 0xC4AEEA),
        bar: Color(light: 0x7B5BB0, dark: 0xC4AEEA)
    )

    // MARK: Polices

    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Bricolage Grotesque", size: size, relativeTo: style).weight(weight)
    }

    /// Taille de base du style à la taille de texte standard : `relativeTo` l'agrandit ensuite une seule fois
    /// selon le réglage de l'utilisateur (Dynamic Type, spec 017, FR-1713).
    static func text(_ style: Font.TextStyle = .body, _ weight: Font.Weight = .regular) -> Font {
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let size = UIFont.preferredFont(forTextStyle: style.uiKit, compatibleWith: standard).pointSize
        return .custom("DM Sans", size: size, relativeTo: style).weight(weight)
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

/// Trio de teintes d'une catégorie : fond doux, texte lisible dessus, barre de progression.
struct MacroPalette {
    let soft: Color
    let ink: Color
    let bar: Color
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
            Text(LocalizedStringKey(title))
                .font(Theme.display(20, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(LocalizedStringKey(trailing))
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
            .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(prominent ? Theme.accent : Theme.card, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Petit bouton en ligne (à côté d'un champ, dans une ligne de liste).
struct CompactButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(.subheadline, .semibold))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(prominent ? Theme.accent : Theme.paper, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension MealType {
    /// Fond et encre de l'icône du repas.
    var tileColors: (background: Color, ink: Color) {
        switch self {
        case .breakfast: (Theme.carbs.soft, Theme.carbs.ink)
        case .lunch: (Theme.successSoft, Theme.success)
        case .snack: (Theme.protein.soft, Theme.protein.ink)
        case .dinner: (Theme.plum.soft, Theme.plum.ink)
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

// MARK: - Listes

/// Titre de section de liste : même police que `SectionTitle`, sans majuscules forcées.
struct ListHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(Theme.display(18, .bold, relativeTo: .headline))
            .foregroundStyle(Theme.ink)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Note sous une section de liste : petite, grise.
struct ListFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(Theme.text(.footnote))
            .foregroundStyle(Theme.muted)
    }
}

/// `Section("Titre")` au style de l'app.
struct ThemedSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            ListHeader { Text(LocalizedStringKey(title)) }
        }
    }
}

/// État vide aux couleurs du thème (contraste AA, contrairement au gris système de ContentUnavailableView).
struct EmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(Theme.display(22, .bold, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Theme.text(.subheadline))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
