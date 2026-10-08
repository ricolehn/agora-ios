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
}

enum Palette {
    static let primary = Color.adaptive(0x06B6D4, 0x22D3EE)
    static let primaryDark = Color.adaptive(0x0E7490, 0x06B6D4)
    static let secondary = Color(hex: 0x10B981)
    static let background = Color.adaptive(0xE6F2FA, 0x0F172A)
    static let surface = Color.adaptive(0xFFFFFF, 0x1E293B)
    static let surfaceAlt = Color.adaptive(0xF8FAFC, 0x334155)
    static let text = Color.adaptive(0x0F172A, 0xF3F4F6)
    static let textSecondary = Color.adaptive(0x64748B, 0x9CA3AF)
    static let border = Color.adaptive(0xCBD5E1, 0x475569)
    static let borderLight = Color.adaptive(0xE2E8F0, 0x334155)
    static let success = Color(hex: 0x10B981)
    static let danger = Color(hex: 0xEF4444)
    static let warning = Color(hex: 0xF59E0B)
    static let amberText = Color.adaptive(0xD97706, 0xFBBF24)
    /// Duties, pinned highlights.
    static let indigo = Color.adaptive(0x6366F1, 0x818CF8)
    /// Messages, dates.
    static let violet = Color.adaptive(0x7C3AED, 0xA78BFA)
    /// Appointments ("Termine"), closed and past things.
    static let slate = Color.adaptive(0x64748B, 0x94A3B8)
    static let pillTrack = Color.adaptive(0xEDF2F7, 0x283548)
    static let shadow = Color.black.opacity(0.06)

    /// 135° cyan → emerald (hero cards, chat bubbles, send buttons, FAB).
    static let brand = LinearGradient(colors: [Color(hex: 0x06B6D4), Color(hex: 0x10B981)], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// 90° cyan → emerald (primary buttons).
    static let button = LinearGradient(colors: [Color(hex: 0x06B6D4), Color(hex: 0x10B981)], startPoint: .leading, endPoint: .trailing)
    static let danger90 = LinearGradient(colors: [Color(hex: 0xEF4444), Color(hex: 0xB91C1C)], startPoint: .leading, endPoint: .trailing)
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
    static let agoraPageTitle = Font.system(size: 22, weight: .heavy)
    /// Section titles ("Deine Dienste").
    static let agoraSection = Font.system(size: 18, weight: .heavy)
    /// Card titles.
    static let agoraCardTitle = Font.system(size: 17, weight: .heavy)
    static let agoraBody = Font.system(size: 15)
    static let agoraMeta = Font.system(size: 13, weight: .medium)
    /// Small caps labels ("OFFENER BETRAG").
    static let agoraCaps = Font.system(size: 11, weight: .heavy)
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
