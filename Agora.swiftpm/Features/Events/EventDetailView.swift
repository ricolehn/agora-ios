import SwiftUI

/// Event page: cover, facts, description, registration, duty roster and management.
struct EventDetailView: View {
    let eventId: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var confirmDelete = false
    @State private var runner = ActionRunner()

    var body: some View {
        Group {
            if let event = store.data.event(eventId) {
                content(event)
            } else if !store.data.loaded {
                LoadingView()
            } else {
                EmptyState(systemImage: "calendar.badge.exclamationmark", title: "Event nicht gefunden")
            }
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private func content(_ event: AgoraEvent) -> some View {
        let hasCover = !event.imageUrl.isEmpty
        // Phones: the cover runs from edge to edge under the status bar. Tablets: it takes the content width.
        let fullBleed = hasCover && sizeClass != .regular
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasCover, let url = store.api.absolute(event.imageUrl) {
                    CoverImage(url: url) {
                        Palette.surfaceAlt
                    } overlay: {
                        if fullBleed {
                            VStack {
                                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 110)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : Radius.card, style: .continuous))
                    .padding(.horizontal, fullBleed ? -20 : 0)
                    .padding(.top, fullBleed ? 0 : 8)
                    .accessibilityHidden(true)
                }
                badges(event)
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if !event.createdByName.isEmpty {
                        (Text("Veranstalter: ") + Text(event.createdByName).bold())
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    groupsLine(event)
                }
                InfoRow(icon: "calendar", color: Palette.violet, label: "Termin", value: Formats.eventWhen(event))
                if !event.location.isEmpty { LocationRow(location: event.location) }
                if !event.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DescriptionCard(event: event)
                }
                if event.requiresRegistration { RegistrationCard(event: event) }
                if event.canAccessDutyPlan { DutyPlanCard(event: event) }
                if event.canEdit { management(event) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: fullBleed ? .top : [])
        .refreshable { await store.refreshEvents() }
        .navigationTitle(fullBleed ? "" : (event.isTermin ? String(localized: "Termin") : String(localized: "Event")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(fullBleed ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if event.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { router.open(.eventEdit(id: event.id, type: event.eventType)) } label: { Label("Bearbeiten", systemImage: "square.and.pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Verwaltung")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(event)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Teilen")
            }
        }
        .confirmationDialog("Möchtest du dieses Event wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Event löschen", role: .destructive) { delete(event) }
        }
    }

    private func badges(_ event: AgoraEvent) -> some View {
        let label: LocalizedStringKey = event.isPinned ? "★ Großevent & Highlight" : (event.isTermin ? "Termin" : "Event")
        return FlowLayout(spacing: 6) {
            CategoryTag(text: label, color: event.isPinned ? Palette.amberText : event.categoryColor)
            if event.isCancelled { CategoryTag(text: "Abgesagt", color: Palette.danger) }
        }
    }

    /// Target groups as a line under the organizer ("Event für die Gruppe „Technik“") instead of tags.
    @ViewBuilder
    private func groupsLine(_ event: AgoraEvent) -> some View {
        let names = event.targetGroups.filter { !$0.isEmpty }.map { store.data.groupName($0) }
            .reduce(into: [String]()) { list, name in if !list.contains(name) { list.append(name) } }
        if !names.isEmpty {
            let quoted = names.map { "„\($0)“" }
            let list = quoted.count > 1 ? quoted.dropLast().joined(separator: ", ") + " und " + (quoted.last ?? "") : quoted[0]
            let lead = "\(event.isTermin ? "Termin" : "Event") für \(names.count == 1 ? "die Gruppe" : "die Gruppen") "
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "person.2.fill").font(.system(size: 12)).foregroundStyle(Palette.indigo)
                (Text(lead) + Text(list).bold().foregroundColor(Palette.text))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func management(_ event: AgoraEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel("Verwaltung")
            HStack(spacing: 10) {
                Button { router.open(.eventEdit(id: event.id, type: event.eventType)) } label: { Label("Bearbeiten", systemImage: "square.and.pencil") }
                    .buttonStyle(.agoraSecondary)
                Button { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
                    .buttonStyle(.agoraDanger)
            }
            .disabled(runner.busy)
        }
        .card()
    }

    private func shareText(_ event: AgoraEvent) -> String {
        var lines = [event.title, Formats.eventWhen(event)]
        if !event.location.isEmpty { lines.append(event.location) }
        return lines.joined(separator: "\n")
    }

    private func delete(_ event: AgoraEvent) {
        runner.run(toasts, success: String(localized: "Event gelöscht")) {
            try await store.repository.deleteEvent(id: event.id)
            await store.refreshAll()
        } done: {
            router.back()
        }
    }
}

/// Info line of the detail page (`.event-detail-quad-cell`).
struct InfoRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    let value: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: icon, color: color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                CapsLabel(label)
                Text(value).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

extension InfoRow where Trailing == EmptyView {
    init(icon: String, color: Color, label: LocalizedStringKey, value: String) {
        self.icon = icon
        self.color = color
        self.label = label
        self.value = value
        self.trailing = EmptyView()
    }
}

/// Address with a button to Apple Maps (not for online meetings).
struct LocationRow: View {
    let location: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        InfoRow(icon: "mappin.and.ellipse", color: Palette.success, label: "Wo / Adresse", value: location) {
            if !Places.isOnline(location), let url = URL(string: "https://maps.apple.com/?q=\(location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Button { openURL(url) } label: {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.success)
                }
                .accessibilityLabel("In Karten öffnen")
            } else if let link = onlineLink {
                Button { openURL(link) } label: {
                    Image(systemName: "video.fill").font(.system(size: 18)).foregroundStyle(Palette.success)
                }
                .accessibilityLabel("Link öffnen")
            }
        }
    }

    private var onlineLink: URL? {
        location.split(separator: " ").first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }.flatMap { URL(string: String($0)) }
    }
}

/// Description clamped to a few lines with a fade and "Mehr anzeigen".
struct DescriptionCard: View {
    let event: AgoraEvent
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    private let collapsed: CGFloat = 110

    var body: some View {
        let overflows = fullHeight > collapsed + 8
        VStack(alignment: .leading, spacing: 10) {
            Label(event.isTermin ? "Über diesen Termin" : "Über dieses Event", systemImage: "text.alignleft")
                .font(.system(size: 12.5, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            MarkdownView(text: event.description)
                .textSelection(.enabled)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
                .frame(maxHeight: expanded || !overflows ? nil : collapsed, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    if overflows && !expanded {
                        LinearGradient(colors: [Palette.surface.opacity(0), Palette.surface], startPoint: .top, endPoint: .bottom).frame(height: 48)
                    }
                }
                .onPreferenceChange(HeightKey.self) { fullHeight = max(fullHeight, $0) }
            if overflows {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Label(expanded ? "Weniger anzeigen" : "Mehr anzeigen", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Palette.primary)
                }
            }
        }
        .card(radius: Radius.nested)
    }
}

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Simple wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
