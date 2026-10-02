import SwiftUI

extension AgoraEvent {
    /// Category color: indigo for highlights, cyan for events, slate for appointments.
    var categoryColor: Color { isPinned ? Palette.indigo : (isTermin ? Palette.slate : Palette.primary) }

    var typeLabel: LocalizedStringKey { isPinned ? "Großevent" : (isTermin ? "Termin" : "Event") }
}

/// Tear-off calendar leaf (`.event-cal`): month strip in the category color, big day, weekday.
struct CalendarLeaf: View {
    let day: String
    var color: Color
    var floating = false

    var body: some View {
        let parts = Formats.leaf(day)
        VStack(spacing: 0) {
            Text(parts.month)
                .font(.system(size: 10.5, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(color)
            Text(parts.day)
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(Palette.text)
                .padding(.top, 2)
            Text(parts.weekday)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, 5)
        }
        .frame(width: 52)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if !floating { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1) }
        }
        .shadow(color: Color(hex: 0x0F172A, opacity: floating ? 0.25 : 0.08), radius: floating ? 7 : 2, y: floating ? 3 : 1)
        .accessibilityElement()
        .accessibilityLabel(Text(Formats.longDay(day)))
    }
}

/// The one status badge of a list card.
struct EventBadgeView: View {
    let badge: EventBadge

    var body: some View {
        switch badge {
        case .duty(let role): StatusPill(text: role, color: Palette.indigo, systemImage: "person.fill")
        case .requestOpen: StatusPill(text: String(localized: "Anfrage offen"), color: Palette.warning, systemImage: "clock")
        case .waitlist: StatusPill(text: String(localized: "Warteliste"), color: Palette.warning, systemImage: "hourglass")
        case .registered: StatusPill(text: String(localized: "Angemeldet"), color: Palette.success, systemImage: "checkmark")
        case .full: StatusPill(text: String(localized: "Ausgebucht"), color: Palette.danger)
        case .openDuties(let count):
            StatusPill(text: count == 1 ? String(localized: "1 Dienst frei") : String(localized: "\(count) Dienste frei"), color: Palette.textSecondary)
        }
    }
}

/// Card of the Termine list and the start page (`.event-card`): category stripe, calendar leaf, title, one
/// "when" line, location, at most one badge.
struct EventRow: View {
    @Environment(AppStore.self) private var store
    let event: AgoraEvent
    /// The day this card stands for (multi-day events appear once per day in Termine).
    var day: String?
    var showRegistered = true

    var body: some View {
        let today = Day.today()
        let shownDay = day ?? event.date
        let isToday = day != nil && day != event.date ? shownDay == today : event.isOngoing(today: today)
        let color = event.categoryColor
        HStack(spacing: 14) {
            CalendarLeaf(day: shownDay, color: event.isTermin && !event.isPinned ? Palette.slate : color)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if isToday {
                        Text("Heute")
                            .font(.system(size: 11, weight: .heavy))
                            .textCase(.uppercase)
                            .foregroundStyle(event.isTermin ? Palette.primary : color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((event.isTermin ? Palette.primary : color).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Label {
                        Text(Formats.eventRowWhen(event)).lineLimit(1)
                    } icon: {
                        Image(systemName: event.isMultiDay ? "calendar" : "clock").opacity(0.65)
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .labelStyle(TightLabelStyle())
                }
                if !event.location.isEmpty {
                    Label { Text(event.location).lineLimit(1) } icon: { Image(systemName: "mappin.and.ellipse") }
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textSecondary)
                        .labelStyle(TightLabelStyle())
                }
            }
            Spacer(minLength: 0)
            if let user = store.user, let badge = EventBadge.of(event, user: user, showRegistered: showRegistered) {
                EventBadgeView(badge: badge)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .background(Palette.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(color.opacity(event.isTermin && !event.isPinned ? 0.45 : 0.85)).frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.list, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.list, style: .continuous)
            .strokeBorder(isToday ? color : Palette.borderLight, lineWidth: isToday ? 2 : 1))
        .shadow(color: Palette.shadow, radius: 6, y: 3)
        .opacity(event.isPast(today: today) ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}

/// Events tab card (`.churchtools-event-card`): 16:9 cover (or gradient), floating leaf, tags, capacity footer.
struct EventCoverCard: View {
    @Environment(AppStore.self) private var store
    let event: AgoraEvent

    var body: some View {
        let past = event.isPast()
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                cover
                CalendarLeaf(day: event.date, color: event.categoryColor, floating: true)
                    .padding(10)
                VStack(alignment: .trailing, spacing: 6) {
                    glassChip(past ? "⌛ Vorbei" : (event.isPinned ? "Großevent" : "Event"))
                    if let user = store.user, let badge = EventBadge.of(event, user: user) {
                        EventBadgeView(badge: badge).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.chip))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text).lineLimit(2)
                VStack(alignment: .leading, spacing: 4) {
                    if event.isMultiDay {
                        Label(Formats.span(event.date, event.endDate), systemImage: "calendar")
                            .foregroundStyle(Palette.primary).fontWeight(.semibold)
                    } else {
                        let time = Formats.clockRange(event.startTime, event.endTime)
                        Label(time.isEmpty ? Formats.mediumDay(event.date) : "\(Formats.mediumDay(event.date)) · \(time)", systemImage: "clock")
                    }
                    if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse").lineLimit(1) }
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .labelStyle(TightLabelStyle())
                Hairline()
                HStack {
                    capacity
                    Spacer()
                    Text("Details ›")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Palette.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Palette.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.chip))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Palette.surface)
        .background(LinearGradient(colors: [(event.isPinned ? Palette.indigo : Palette.primary).opacity(0.05), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: Radius.list, style: .continuous))
        .shadow(color: Palette.shadow, radius: 6, y: 3)
        .opacity(past ? 0.65 : 1)
        .accessibilityElement(children: .combine)
    }

    /// 16:9 cover over the full card width; without a picture a gradient with a calendar tile.
    private var cover: some View {
        let url = store.api.absolute(event.imageUrl)
        return CoverImage(url: url) {
            ZStack {
                LinearGradient(colors: [Palette.primary.opacity(0.25), Palette.indigo.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "calendar")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } overlay: {
            if url != nil {
                LinearGradient(stops: [.init(color: .black.opacity(0.18), location: 0), .init(color: .clear, location: 0.45),
                                       .init(color: .black.opacity(0.28), location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func glassChip(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background((event.isPinned ? Color(hex: 0x6366F1) : Color(hex: 0x0E7490)).opacity(0.75), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var capacity: some View {
        if !event.requiresRegistration {
            Text("Ohne Anmeldung").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.textSecondary)
        } else if event.maxParticipants > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(event.registeredCount) / \(event.maxParticipants) Plätze").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                CapsuleProgress(value: Double(event.registeredCount) / Double(max(event.maxParticipants, 1)), height: 4).frame(width: 110)
            }
        } else {
            Text("\(event.registeredCount) angemeldet").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
        }
    }
}

/// "Offene Dienstanfragen an dich": answer requests right here.
struct DutyRequestCard: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router
    @State private var runner = ActionRunner()

    var body: some View {
        let requests = store.data.dutyRequests
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(systemImage: "tray.and.arrow.down", color: Palette.indigo, size: 34)
                Text("Offene Dienstanfragen an dich (\(requests.count))").font(.system(size: 15.5, weight: .bold)).foregroundStyle(Palette.text)
                Spacer(minLength: 0)
            }
            Text("Rückmeldung erbeten")
                .font(.system(size: 11, weight: .heavy)).textCase(.uppercase).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Palette.warning, in: Capsule())
            ForEach(requests) { request in
                VStack(alignment: .leading, spacing: 6) {
                    Button { router.open(.event(request.eventId)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.eventTitle).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                            let time = Formats.clockRange(request.eventStartTime, request.eventEndTime)
                            Label(time.isEmpty ? Formats.longDay(request.eventDate) : "\(Formats.longDay(request.eventDate)) · \(time)", systemImage: "calendar")
                                .font(.system(size: 13)).foregroundStyle(Palette.textSecondary).labelStyle(TightLabelStyle())
                            roleLine(request)
                            if !request.notes.isEmpty {
                                Text(request.notes).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        Button { respond(request, accept: true) } label: { Label("Zusagen", systemImage: "checkmark") }
                            .buttonStyle(.agoraPrimary(small: true))
                        Button { respond(request, accept: false) } label: { Label("Ablehnen", systemImage: "xmark") }
                            .buttonStyle(.agoraDanger(small: true))
                    }
                    .disabled(runner.busy)
                }
                .padding(12)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.nested, style: .continuous))
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Palette.indigo.opacity(0.08), Palette.warning.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.indigo.opacity(0.25), lineWidth: 1))
    }

    private func roleLine(_ request: DutyRequest) -> some View {
        var rest = ""
        if !request.section.isEmpty && request.section != "Allgemein" { rest += " · \(request.section)" }
        if !request.requestedByName.isEmpty { rest += " (angefragt von \(request.requestedByName))" }
        let text = Text(request.roleName.isEmpty ? "Dienst" : request.roleName).bold() + Text(rest)
        return Label { text } icon: { Image(systemName: "wrench.and.screwdriver") }
            .font(.system(size: 13.5)).foregroundStyle(Palette.text).labelStyle(TightLabelStyle())
    }

    private func respond(_ request: DutyRequest, accept: Bool) {
        runner.run(toasts, success: accept ? "Dienst zugesagt" : "Dienst abgelehnt") {
            try await store.repository.respondToDuty(id: request.id, accept: accept)
            store.update { $0.dutyRequests.removeAll { $0.id == request.id } }
            await store.refreshAll()
        }
    }
}
