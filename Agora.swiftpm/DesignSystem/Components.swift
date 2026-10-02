import SwiftUI

// MARK: - Cards

/// `.card` of the web app: surface, rounded, hairline border and a very soft shadow.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Radius.card
    var padding: CGFloat? = 16
    var border: Color = Palette.borderLight
    var fill: Color = Palette.surface

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1))
            .shadow(color: Palette.shadow, radius: 6, x: 0, y: 3)
    }
}

extension View {
    func card(radius: CGFloat = Radius.card, padding: CGFloat? = 16, border: Color = Palette.borderLight, fill: Color = Palette.surface) -> some View {
        modifier(CardBackground(radius: radius, padding: padding, border: border, fill: fill))
    }

    /// Tinted status card (green / amber / red at 8 %, border at 25 %).
    func tintedCard(_ color: Color, radius: CGFloat = Radius.card, padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 2))
    }
}

// MARK: - Buttons

/// Gradient button (`.btn-primary`).
struct PrimaryButtonStyle: ButtonStyle {
    var small = false
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 14 : 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, small ? 8 : 13)
            .padding(.horizontal, small ? 14 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Palette.button, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined light button (`.btn-secondary`).
struct SecondaryButtonStyle: ButtonStyle {
    var small = false
    var fullWidth = true
    var tint: Color = Palette.text
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 14 : 16, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.vertical, small ? 8 : 12)
            .padding(.horizontal, small ? 14 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Red tinted button (`.btn-danger`).
struct DangerButtonStyle: ButtonStyle {
    var small = false
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 14 : 16, weight: .semibold))
            .foregroundStyle(Palette.danger)
            .padding(.vertical, small ? 8 : 12)
            .padding(.horizontal, small ? 14 : 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Cards and rows that shrink a little while pressed, like the web app's `:active` states.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var agoraPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func agoraPrimary(small: Bool = false, fullWidth: Bool = true) -> PrimaryButtonStyle { PrimaryButtonStyle(small: small, fullWidth: fullWidth) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var agoraSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func agoraSecondary(small: Bool = false, fullWidth: Bool = true, tint: Color = Palette.text) -> SecondaryButtonStyle {
        SecondaryButtonStyle(small: small, fullWidth: fullWidth, tint: tint)
    }
}

extension ButtonStyle where Self == DangerButtonStyle {
    static var agoraDanger: DangerButtonStyle { DangerButtonStyle() }
    static func agoraDanger(small: Bool = false, fullWidth: Bool = true) -> DangerButtonStyle { DangerButtonStyle(small: small, fullWidth: fullWidth) }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Button label with a spinner while an action runs.
struct BusyLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var busy: Bool

    var body: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().tint(.white).controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }
}

// MARK: - Pill tabs (segmented control of the web app)

struct PillTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: LocalizedStringKey
        var systemImage: String?
        var badge: Int = 0
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                let active = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item.value }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = item.systemImage { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                        Text(item.title).lineLimit(1).minimumScaleFactor(0.8)
                        if item.badge > 0 { CountBadge(count: item.badge) }
                    }
                    .font(.system(size: 14, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? Palette.text : Palette.textSecondary)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        if active {
                            Capsule().fill(Palette.surface)
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.pillTrack, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.borderLight, lineWidth: 1))
    }
}

// MARK: - Search

/// Capsule search field of the web app.
struct SearchField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Palette.surfaceAlt, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.borderLight, lineWidth: 1))
    }
}

// MARK: - Badges

/// Rounded status badge (`.event-card-status`).
struct StatusPill: View {
    let text: String
    var color: Color
    var systemImage: String?
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(filled ? .white : color)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(filled ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(color.opacity(filled ? 0 : 0.25), lineWidth: 1))
    }
}

/// Small capsule with a number ("99+" above 99).
struct CountBadge: View {
    let count: Int
    var color: Color = Palette.primary

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(color, in: Capsule())
    }
}

/// Capsule category tag ("EVENT", "GROSSEVENT").
struct CategoryTag: View {
    let text: LocalizedStringKey
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.vertical, 2)
            .padding(.horizontal, 9)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Headers

/// Month / section header: caps title, optional count, hairline filling the row.
struct SectionHeader: View {
    let title: String
    var count: Int?
    var color: Color = Palette.textSecondary

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(color)
            if let count {
                Text("(\(count))").font(.system(size: 12, weight: .semibold)).foregroundStyle(color.opacity(0.8))
            }
            Rectangle().fill(Palette.borderLight).frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Page title row with an optional trailing control.
struct PageTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    var trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.agoraPageTitle).tracking(-0.4).foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

// MARK: - Misc

/// Colored square with an icon (card heads, info rows).
struct IconTile: View {
    let systemImage: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.primary)
                .frame(width: 64, height: 64)
                .background(Palette.primary.opacity(0.12), in: Circle())
                .padding(.bottom, 4)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}

/// Thin capsule progress bar.
struct CapsuleProgress: View {
    let value: Double
    var fill: LinearGradient = Palette.button
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceAlt)
                Capsule().fill(fill).frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((min(max(value, 0), 1)) * 100)) %"))
    }
}

/// Small key/value tile ("MONATSBEITRAG 12,00 €").
struct StatCell: View {
    let label: LocalizedStringKey
    let value: String
    var valueColor: Color = Palette.text

    var body: some View {
        VStack(spacing: 4) {
            CapsLabel(label)
            Text(value).font(.system(size: 16, weight: .heavy)).foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Hairline divider in the border color.
struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.borderLight).frame(height: 1) }
}

/// Loading state for whole screens.
struct LoadingView: View {
    var text: LocalizedStringKey = "Lade Daten…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(Palette.primary)
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Gradient-filled text (app name in the header and on the login screen).
struct GradientText: View {
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Palette.brand)
    }
}
