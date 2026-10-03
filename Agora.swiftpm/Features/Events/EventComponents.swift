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

/// Soft color mesh where an event has no picture (`.ct-event-card-fallback-cover`): radial spots over surfaceAlt.
struct ColorMesh: View {
    let spots: [(point: UnitPoint, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height) * 0.55
            ZStack {
                Palette.surfaceAlt
                ForEach(spots.indices, id: \.self) { index in
                    RadialGradient(colors: [spots[index].color, .clear], center: spots[index].point, startRadius: 0, endRadius: radius)
                }
            }
        }
    }

    static func event(pinned: Bool) -> ColorMesh {
        pinned
            ? ColorMesh(spots: [(point: UnitPoint(x: 0.2, y: 0.25), color: Color(hex: 0x6366F1, opacity: 0.42)),
                                (point: UnitPoint(x: 0.85, y: 0.3), color: Color(hex: 0x06B6D4, opacity: 0.32)),
                                (point: UnitPoint(x: 0.5, y: 1), color: Color(hex: 0xA855F7, opacity: 0.25))])
            : ColorMesh(spots: [(point: UnitPoint(x: 0.18, y: 0.22), color: Color(hex: 0x06B6D4, opacity: 0.38)),
                                (point: UnitPoint(x: 0.82, y: 0.28), color: Color(hex: 0x6366F1, opacity: 0.32)),
                                (point: UnitPoint(x: 0.55, y: 1), color: Color(hex: 0x10B981, opacity: 0.28))])
    }
}

/// Events tab card like the web app (beta16): the 16:9 picture sits inset with its own rounded corners, frosted
/// labels on it, a color mesh without a picture, bold title with the own registration next to it, colored meta
/// icons, capacity and a round arrow. Highlights get a gradient frame, past pictures lose their color.
struct EventCoverCard: View {
    @Environment(AppStore.self) private var store
    let event: AgoraEvent

    private var accent: Color { event.isPinned ? Palette.indigo : Palette.primary }

    var body: some View {
        let past = event.isPast()
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                cover(past: past)
                CalendarLeaf(day: event.date, color: event.categoryColor, floating: true)
                    .padding(10)
                HStack(spacing: 6) {
                    coverLabel
                    status(past: past)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Own registration next to the title, independent of the status on the picture
                    if event.isRegistered && !past {
                        StatusPill(text: String(localized: "Angemeldet"), color: Palette.success, systemImage: "checkmark")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if event.isMultiDay {
                        meta("calendar", Formats.span(event.date, event.endDate), color: event.isPinned ? accent : Palette.text, bold: true)
                    } else {
                        let time = Formats.clockRange(event.startTime, event.endTime)
                        meta("clock", time.isEmpty ? Formats.mediumDay(event.date) : "\(Formats.mediumDay(event.date)) · \(time)")
                    }
                    if !event.location.isEmpty { meta("mappin.and.ellipse", event.location) }
                }
                HStack(spacing: 10) {
                    capacity
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 40, height: 40)
                        .background(Palette.surfaceAlt, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.borderLight, lineWidth: 1))
                        .accessibilityHidden(true)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
        .padding(8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if event.isPinned {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color(hex: 0x6366F1), Color(hex: 0x06B6D4), Color(hex: 0x10B981)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1)
            }
        }
        .shadow(color: event.isPinned ? Color(hex: 0x6366F1, opacity: 0.22) : Color(hex: 0x0F172A, opacity: 0.1), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// 16:9 picture, or the color mesh with a frosted calendar tile; darker edges keep the labels readable.
    private func cover(past: Bool) -> some View {
        CoverImage(url: store.api.absolute(event.imageUrl)) {
            ZStack {
                ColorMesh.event(pinned: event.isPinned)
                Image(systemName: "calendar")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color(hex: 0x0F172A, opacity: 0.2), radius: 10, y: 6)
            }
        } overlay: {
            LinearGradient(stops: [.init(color: Color(hex: 0x0F172A, opacity: 0.28), location: 0), .init(color: .clear, location: 0.34),
                                   .init(color: .clear, location: 0.7), .init(color: Color(hex: 0x0F172A, opacity: 0.18), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .saturation(past ? 0.3 : 1)
        .background(Palette.surfaceAlt)
    }

    /// Frosted "EVENT" / "GROSSEVENT" label (indigo for highlights).
    private var coverLabel: some View {
        Text(event.isPinned ? "Großevent" : "Event")
            .font(.system(size: 11, weight: .heavy))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(event.isPinned ? Color(hex: 0x4F46E5, opacity: 0.62) : Color(hex: 0x0F172A, opacity: 0.38), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(event.isPinned ? 0.45 : 0.35), lineWidth: 1))
    }

    /// Light status chip on the picture: past, own duty, open request, waiting list, full.
    @ViewBuilder
    private func status(past: Bool) -> some View {
        if past {
            statusChip(String(localized: "⌛ Vorbei"), color: Palette.slate, icon: nil)
        } else if let user = store.user, let badge = EventBadge.of(event, user: user, showRegistered: false) {
            switch badge {
            case .duty(let role): statusChip(role, color: Palette.indigo, icon: "person.fill")
            case .requestOpen: statusChip(String(localized: "Anfrage offen"), color: Palette.amberText, icon: "clock")
            case .waitlist: statusChip(String(localized: "Warteliste"), color: Palette.amberText, icon: "hourglass")
            case .full: statusChip(String(localized: "Ausgebucht"), color: Palette.danger, icon: nil)
            case .registered, .openDuties: EmptyView()
            }
        }
    }

    private func statusChip(_ text: String, color: Color, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11.5, weight: .heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.surface.opacity(0.88), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func meta(_ icon: String, _ text: String, color: Color = Palette.textSecondary, bold: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 14, weight: bold ? .bold : .regular))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var capacity: some View {
        if !event.requiresRegistration {
            footerPill(String(localized: "Ohne Anmeldung"))
        } else if event.maxParticipants > 0 {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(event.registeredCount)/\(event.maxParticipants) Plätze").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Palette.text)
                CapsuleProgress(value: Double(event.registeredCount) / Double(max(event.maxParticipants, 1)), height: 6).frame(width: 120)
            }
        } else {
            footerPill(String(localized: "\(event.registeredCount) angemeldet"))
        }
    }

    private func footerPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Palette.surfaceAlt, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.borderLight, lineWidth: 1))
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
