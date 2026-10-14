import SwiftUI
import UIKit

// Design tokens of the web app (assets/style.css), light and dark. The web app is the reference for the look.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) { self.init(uiColor: UIColor(hex: hex, alpha: opacity)) }

    /// Follows the light/dark appearance (also the in-app theme choice).
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// Like `adaptive`, with an opacity per appearance.
    static func adaptive(_ light: UInt32, _ lightOpacity: CGFloat, _ dark: UInt32, _ darkOpacity: CGFloat) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkOpacity) : UIColor(hex: light, alpha: lightOpacity) })
    }
}

// Palette "Stone & Lagoon" of web v3.1 ORION (assets/polish.css): warm stone neutrals and a deep lagoon teal that
// runs into emerald. The dark theme is tuned on its own: barely warm near-black, softer off-white text, dimmed
// accents and no coloured light.
enum Palette {
    static let primary = Color.adaptive(0x0C8D84, 0x63C0B4)
    static let primaryDark = Color.adaptive(0x0B7D75, 0x2EA398)
    static let secondary = Color.adaptive(0x14A87C, 0x3FAE84)
    static let background = Color.adaptive(0xF5F4F1, 0x181817)
    static let surface = Color.adaptive(0xFFFFFF, 0x222120)
    static let surfaceAlt = Color.adaptive(0xF1EFEB, 0x2B2A28)
    static let text = Color.adaptive(0x1A1917, 0xEBE8E3)
    static let textSecondary = Color.adaptive(0x6D6861, 0xA3A09A)
    static let border = Color.adaptive(0xD9D5CD, 0x45433F)
    static let borderLight = Color.adaptive(0xE8E5DF, 0x343230)
    static let success = Color.adaptive(0x0F9B6C, 0x5BB48B)
    static let danger = Color.adaptive(0xE5484D, 0xDE6F72)
    static let warning = Color.adaptive(0xE0900F, 0xD4A24E)
    static let amberText = Color.adaptive(0xB86E06, 0xD4A24E)
    /// Duties, pinned highlights.
    static let indigo = Color.adaptive(0x6366F1, 0x818CF8)
    /// Messages, dates.
    static let violet = Color.adaptive(0x7C3AED, 0xA78BFA)
    /// Appointments ("Termine"), closed and past things: warm stone.
    static let slate = Color.adaptive(0x78716C, 0xA8A29E)
    static let pillTrack = Color.adaptive(0xF1EFEB, 0x2B2A28)
    /// Shadows: warm stone in light, plain black in dark (never coloured light).
    static let shadow = Color.adaptive(0x30261A, 0.07, 0x000000, 0.35)

    /// 135° lagoon → emerald (hero cards, send buttons, FAB).
    static let brand = LinearGradient(colors: [Color.adaptive(0x0E9F96, 0x0F8E86), Color.adaptive(0x17AD80, 0x159A72)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    /// 90° lagoon → emerald (primary buttons).
    static let button = LinearGradient(colors: [Color.adaptive(0x0E9F96, 0x0F8E86), Color.adaptive(0x17AD80, 0x159A72)],
                                       startPoint: .leading, endPoint: .trailing)
    static let danger90 = LinearGradient(colors: [Color(hex: 0xE5484D), Color(hex: 0xB91C1C)], startPoint: .leading, endPoint: .trailing)
}

/// Corner radii of the web app.
enum Radius {
    static let hero: CGFloat = 28
    static let card: CGFloat = 20
    static let large: CGFloat = 18
    static let list: CGFloat = 16
    static let nested: CGFloat = 14
    static let control: CGFloat = 12
    static let chip: CGFloat = 8
}

extension Font {
    /// Page titles ("Termine & Events").
    static let agoraPageTitle = Font.system(size: 22, weight: .bold)
    /// Section titles ("Deine Dienste").
    static let agoraSection = Font.system(size: 18, weight: .bold)
    /// Card titles.
    static let agoraCardTitle = Font.system(size: 17, weight: .bold)
    static let agoraBody = Font.system(size: 15)
    static let agoraMeta = Font.system(size: 13, weight: .medium)
    /// Small caps labels ("OFFENER BETRAG").
    static let agoraCaps = Font.system(size: 11, weight: .bold)
}

/// Caps label as in the web app: uppercase, letter-spaced, secondary color.
struct CapsLabel: View {
    let text: LocalizedStringKey
    var color: Color = Palette.textSecondary

    init(_ text: LocalizedStringKey, color: Color = Palette.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.agoraCaps)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// App-wide color scheme choice (Settings → Darstellung).
enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    /// The same as text (e.g. a summary line).
    var name: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Hell")
        case .dark: return String(localized: "Dunkel")
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
