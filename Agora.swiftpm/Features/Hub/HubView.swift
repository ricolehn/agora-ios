import SwiftUI

/// A tile of the Extras hub (web: HUB_APPS).
struct HubApp: Identifiable {
    let route: Route
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    var id: String { "\(route)" }

    /// The apps of the hub; the AI chat only when it is switched on and the person may use it. Polls stay off (v3.1).
    static func available(aiAvailable: Bool) -> [HubApp] {
        var apps: [HubApp] = []
        if aiAvailable {
            apps.append(HubApp(route: .ai, icon: "sparkles", color: Color(hex: 0x7C3AED),
                               title: "KI-Support", description: "Fragen zur Gemeinde, zu Terminen und Finanzen"))
        }
        apps.append(HubApp(route: .songbook, icon: "music.note", color: Color(hex: 0x0891B2),
                           title: "Liederbuch", description: "Lieder und Texte für Gottesdienst und Kleingruppe"))
        apps.append(HubApp(route: .prayers, icon: "heart", color: Prayers.rose,
                           title: "Gebetsanliegen", description: "Anliegen teilen und füreinander beten"))
        return apps
    }
}

/// Extras: one permanent tab for further apps of the community (web: #hub).
struct HubView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let aiAvailable = (store.user?.accessesAi ?? false) && store.data.aiEnabled
        TabPage(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extras").font(.agoraPageTitle).tracking(-0.4).foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Weitere Angebote der Gemeinde an einem Ort.").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            }
            .padding(.bottom, 6)
            ForEach(HubApp.available(aiAvailable: aiAvailable)) { app in
                Button { router.open(app.route) } label: { HubTile(app: app) }
                    .buttonStyle(.pressable)
            }
        }
    }
}

private struct HubTile: View {
    let app: HubApp

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: app.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(app.color)
                .frame(width: 48, height: 48)
                .background(app.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Text(app.description).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.6))
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
