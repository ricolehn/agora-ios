import SwiftUI
import UIKit

/// Share an event (web: #event-share-modal, Android: EventShareSheet): its link to copy or to hand to the share sheet.
/// Whoever may edit the event decides with the switch whether people without an account can open it and sign up as
/// guests (servers from v3.2 on; older ones send no switch state, then there is no switch and the members' link).
struct EventShareSheet: View {
    let eventId: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The switch shows the new state while the server saves it; the event (and the link) follow on the refresh.
    @State private var pending: Bool?
    @State private var saving = false
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let event = store.data.event(eventId) {
                    content(event)
                } else {
                    EmptyState(systemImage: "calendar.badge.exclamationmark", title: "Event nicht gefunden")
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }

    private func content(_ event: AgoraEvent) -> some View {
        let isPublic = pending ?? (event.isPublic == true)
        let link = EventLinks.shareURL(baseURL: store.baseURL, event: event, among: store.data.events)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "square.and.arrow.up", color: Palette.primary, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                        Text(Formats.eventWhen(event)).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if event.canEdit && event.isPublic != nil {
                    publicSwitch(event, isOn: isPublic)
                }
                VStack(alignment: .leading, spacing: 8) {
                    CapsLabel("Link")
                    Text(link)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
                    // Who can open the link
                    Label(isPublic ? "Jeder mit diesem Link kann das Event sehen." : "Nur Mitglieder können diesen Link öffnen.",
                          systemImage: isPublic ? "eye" : "lock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isPublic ? Palette.primary : Palette.textSecondary)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { actions(event, link: link) }
    }

    private func publicSwitch(_ event: AgoraEvent, isOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { isOn }, set: { setPublic($0, event: event) })) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "globe", color: Palette.primary, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ohne Konto sichtbar").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                        Text(event.requiresRegistration
                             ? "Wer den Link hat, sieht das Event und kann sich anmelden – ganz ohne Konto."
                             : "Wer den Link hat, sieht das Event – ganz ohne Konto.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Palette.primary)
            .disabled(saving)
            .card(radius: Radius.nested, padding: 14)
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(Palette.danger)
            }
        }
    }

    private func actions(_ event: AgoraEvent, link: String) -> some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = link
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
            } label: {
                Label(copied ? "Kopiert" : "Link kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.agoraSecondary)
            // The link alone (messengers show the event's title and picture from it); the title for e-mail
            Group {
                if let url = URL(string: link) {
                    ShareLink(item: url, subject: Text(event.title)) { Label("Teilen …", systemImage: "square.and.arrow.up") }
                } else {
                    ShareLink(item: link, subject: Text(event.title)) { Label("Teilen …", systemImage: "square.and.arrow.up") }
                }
            }
            .buttonStyle(.agoraPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Only those who may edit the event get the switch; the server checks it again.
    private func setPublic(_ on: Bool, event: AgoraEvent) {
        guard !saving else { return }
        pending = on
        error = nil
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.repository.setEventPublic(eventId: event.id, on)
                await store.refreshEvents()
            } catch {
                self.error = APIError.text(error)
            }
            pending = nil
        }
    }
}
