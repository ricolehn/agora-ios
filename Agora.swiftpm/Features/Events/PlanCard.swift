import SwiftUI

// One plan per event (web v3.1 ORION): duty roster and order of service merged. Entries in the order get their time
// from the start and the durations, the others follow as tasks "during the whole event". People are always asked
// through the duty roster, so requests, answers and reminders keep working. Like PlanCard.kt of the Android app.

enum Plan {
    static let missingSong = String(localized: "Lied (nicht mehr im Liederbuch)")

    static func isTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":")
        return parts.count == 2 && (1...2).contains(parts[0].count) && parts[1].count == 2 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    static func addMinutes(_ hhmm: String, _ minutes: Int) -> String {
        let parts = hhmm.split(separator: ":").map { Int($0) ?? 0 }
        guard parts.count == 2 else { return hhmm }
        let total = (((parts[0] * 60 + parts[1] + minutes) % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Start time of every item (empty without an event start time).
    static func times(_ items: [ProgramItem], start: String) -> [String] {
        guard isTime(start) else { return items.map { _ in "" } }
        var offset = 0
        return items.map { item in
            defer { offset += item.minutes ?? 0 }
            return addMinutes(start, offset)
        }
    }

    static func total(_ items: [ProgramItem]) -> Int { items.reduce(0) { $0 + ($1.minutes ?? 0) } }

    static func sameName(_ a: String?, _ b: String?) -> Bool {
        (a ?? "").trimmingCharacters(in: .whitespaces).lowercased() == (b ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Title of an item: its own, else the song's title, else "song (missing)".
    static func itemTitle(_ item: ProgramItem, _ songs: [PlanSong]) -> String {
        if !item.title.trimmingCharacters(in: .whitespaces).isEmpty { return item.title }
        if let song = songs.first(where: { $0.id == item.songId }) { return song.title }
        return item.songId.isEmpty ? "" : missingSong
    }

    /// The roster task of an item: the one named under "who", else the one with the item's title.
    static func itemTask(_ item: ProgramItem, _ roles: [String], _ songs: [PlanSong]) -> String? {
        roles.first { sameName($0, item.who) } ?? roles.first { sameName($0, itemTitle(item, songs)) }
    }

    static func roleNames(_ event: AgoraEvent) -> [String] {
        var names: [String] = []
        for duty in event.duties {
            let name = duty.roleName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Confirmed people and assigned groups count as filled.
    static func filled(_ duties: [Duty]) -> Int { duties.filter(\.isFilled).count }

    /// The duties of every task in the order they first appear.
    static func grouped(_ duties: [Duty]) -> [(role: String, duties: [Duty])] {
        var order: [String] = []
        var map: [String: [Duty]] = [:]
        for duty in duties {
            let role = duty.roleName.trimmingCharacters(in: .whitespaces)
            guard !role.isEmpty else { continue }
            if map[role] == nil { order.append(role) }
            map[role, default: []].append(duty)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

extension Duty {
    /// A group holds the task.
    var planIsGroup: Bool { status == "assigned" && isGroup }
}

/// What the entry sheet opens: a new entry, an order item (and its task) or a task without a time.
struct PlanEntryTarget: Identifiable {
    var itemId: String?
    var role: String?
    var isNew = false
    var id: String { isNew ? "new" : "\(itemId ?? "-")|\(role ?? "-")" }
}

/// The plan card of the event detail: head with "x von y besetzt · 10:00 – 10:24", then one calm list - the order of
/// service as a timeline (time or place number + minutes), the tasks without a time below. Editors tap a row to
/// open its entry; "Eintrag hinzufügen" adds a task or a song.
struct PlanCard: View {
    let event: AgoraEvent
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var runner = ActionRunner()
    @State private var items: [ProgramItem] = []
    @State private var songs: [PlanSong] = []
    @State private var expanded = false
    @State private var entry: PlanEntryTarget?
    @State private var reload = 0

    var body: some View {
        let duties = event.duties
        let roles = Plan.roleNames(event)
        let filled = Plan.filled(duties)
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconTile(systemImage: "wrench.and.screwdriver", color: Palette.indigo, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items.isEmpty ? "Dienstplan" : "Dienstplan & Ablauf").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                        Text(meta(roles: roles, filled: filled)).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Zuklappen" : "Aufklappen")
            if !duties.isEmpty {
                CapsuleProgress(value: Double(filled) / Double(max(duties.count, 1)),
                                fill: filled == duties.count ? Palette.button
                                    : LinearGradient(colors: [Color(hex: 0x818CF8), Color(hex: 0x6366F1)], startPoint: .leading, endPoint: .trailing))
            }
            if expanded { list(roles: roles) }
        }
        .card()
        .task(id: "\(event.id)|\(event.duties.hashValue)|\(reload)") { await loadProgram() }
        .sheet(item: $entry, onDismiss: { reload += 1 }) { target in
            PlanEntrySheet(event: event, items: $items, target: target)
        }
    }

    private func meta(roles: [String], filled: Int) -> String {
        let duties = event.duties
        let filledText = duties.isEmpty ? "" : String(localized: "\(filled) von \(duties.count) besetzt")
        if !items.isEmpty {
            let total = Plan.total(items)
            let times = Plan.times(items, start: event.startTime)
            let span: String
            if total == 0 {
                span = ""
            } else if let first = times.first, !first.isEmpty {
                span = "\(event.startTime) – \(Plan.addMinutes(event.startTime, total))"
            } else {
                span = String(localized: "\(total) Min.")
            }
            let joined = [filledText, span].filter { !$0.isEmpty }.joined(separator: " · ")
            if !joined.isEmpty { return joined }
            return items.count == 1 ? String(localized: "1 Punkt") : String(localized: "\(items.count) Punkte")
        }
        if duties.isEmpty { return String(localized: "Noch keine Aufgaben") }
        return filledText + " · " + (roles.count == 1 ? String(localized: "1 Aufgabe") : String(localized: "\(roles.count) Aufgaben"))
    }

    @ViewBuilder
    private func list(roles: [String]) -> some View {
        let grouped = Plan.grouped(event.duties)
        let dutiesOf: (String) -> [Duty] = { role in grouped.first { $0.role == role }?.duties ?? [] }
        let rows: [(index: Int, item: ProgramItem, role: String?)] = items.enumerated().map { ($0.offset, $0.element, Plan.itemTask($0.element, roles, songs)) }
        let used = Set(rows.compactMap { $0.role })
        let tasks = grouped.filter { !used.contains($0.role) }
        let times = Plan.times(items, start: event.startTime)
        let both = !rows.isEmpty && !tasks.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty && tasks.isEmpty {
                Text(event.canEdit ? "Füge hinzu, was passiert und wer hilft – mit „Eintrag hinzufügen“ unten." : "Für dieses Event sind keine Dienste eingetragen.")
                    .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    .padding(.vertical, 8)
            }
            if both {
                Label("Ablauf", systemImage: "clock")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .labelStyle(TightLabelStyle())
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { position, row in
                if position > 0 { Hairline().padding(.leading, 58) }
                let minutes = row.item.minutes ?? 0
                let song = songs.first { $0.id == row.item.songId }
                let key = row.item.songKey.isEmpty ? (song?.key ?? "") : row.item.songKey
                let title = Plan.itemTitle(row.item, songs)
                PlanRow(
                    time: minutes > 0 && !times[row.index].isEmpty ? times[row.index] : "\(row.index + 1).",
                    minutes: minutes > 0 ? minutes : nil,
                    title: title,
                    songKey: !row.item.songId.isEmpty && !key.isEmpty ? key : nil,
                    people: row.role.map(dutiesOf),
                    textWho: row.role == nil && !row.item.who.trimmingCharacters(in: .whitespaces).isEmpty && !Plan.sameName(row.item.who, title) ? row.item.who : nil,
                    note: row.item.note,
                    busy: runner.busy,
                    onRespond: respond,
                    onOpen: event.canEdit ? { entry = PlanEntryTarget(itemId: row.item.id, role: row.role) } : nil
                )
            }
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { position, task in
                        if position > 0 { Hairline() }
                        PlanRow(
                            time: nil, minutes: nil, title: task.role, songKey: nil,
                            people: task.duties, textWho: nil,
                            note: task.duties.first { !$0.notes.isEmpty }?.notes ?? "",
                            busy: runner.busy,
                            onRespond: respond,
                            onOpen: event.canEdit ? { entry = PlanEntryTarget(itemId: nil, role: task.role) } : nil
                        )
                    }
                }
                .padding(.horizontal, both ? 12 : 0)
                .background {
                    if both { RoundedRectangle(cornerRadius: Radius.nested, style: .continuous).fill(Palette.surfaceAlt) }
                }
                .overlay {
                    if both { RoundedRectangle(cornerRadius: Radius.nested, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1) }
                }
                .padding(.top, both ? 10 : 0)
            }
            if event.canEdit {
                Button { entry = PlanEntryTarget(isNew: true) } label: { Label("Eintrag hinzufügen", systemImage: "plus") }
                    .buttonStyle(.agoraSecondary)
                    .padding(.top, 12)
            }
        }
        .disabled(runner.busy)
        .transition(.opacity)
    }

    private func loadProgram() async {
        guard let program = try? await store.repository.program(eventId: event.id) else { return }
        items = program.items
        if program.items.contains(where: { !$0.songId.isEmpty }) && songs.isEmpty {
            songs = (try? await store.repository.planSongs()) ?? []
        }
    }

    private func respond(_ duty: Duty, _ accept: Bool) {
        runner.run(toasts, success: accept ? String(localized: "Dienst zugesagt") : String(localized: "Dienst abgelehnt")) {
            try await store.repository.respondToDuty(id: duty.id, accept: accept)
            await store.refreshEvents()
        }
    }
}

/// One row of the plan: time column (order items only), title, people right under it, note, answer buttons.
private struct PlanRow: View {
    let time: String?
    let minutes: Int?
    let title: String
    let songKey: String?
    let people: [Duty]?
    let textWho: String?
    let note: String
    let busy: Bool
    let onRespond: (Duty, Bool) -> Void
    let onOpen: (() -> Void)?
    @Environment(AppStore.self) private var store

    var body: some View {
        let me = store.user?.userId ?? ""
        let request = people?.first { $0.isRequested && $0.requestedUser == me }
        HStack(alignment: .top, spacing: 0) {
            if let time {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(time).font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(time.contains(":") ? Palette.text : Palette.textSecondary)
                    if let minutes {
                        Text("\(minutes) Min.").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 8)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(2)
                    if let songKey { PlanKeyChip(key: songKey) }
                }
                Group {
                    if let people {
                        PlanPeopleShort(duties: people)
                    } else if let textWho {
                        Text(textWho).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
                    } else {
                        PlanOpenLabel()
                    }
                }
                if !note.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(note).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
                }
                if let request {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Du wurdest angefragt").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.amberText)
                        HStack(spacing: 6) {
                            Button { onRespond(request, true) } label: { Label("Zusagen", systemImage: "checkmark") }
                                .buttonStyle(.agoraPrimary(small: true, fullWidth: false))
                            Button("Ablehnen") { onRespond(request, false) }
                                .buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                        }
                        .disabled(busy)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if onOpen != nil {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.5))
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityAddTraits(onOpen != nil ? .isButton : [])
    }
}

struct PlanKeyChip: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Palette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Tonart \(key)")
    }
}

struct PlanOpenLabel: View {
    var long = false

    var body: some View {
        Text(long ? "noch offen" : "offen").font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary.opacity(0.8))
    }
}

/// The people of a row: small picture, first name and "angefragt" / "abgelehnt"; more than three as "+N".
private struct PlanPeopleShort: View {
    let duties: [Duty]

    var body: some View {
        let people = duties.filter(\.hasAssignee)
        if people.isEmpty {
            PlanOpenLabel()
        } else {
            let shown = people.count > 3 ? Array(people.prefix(2)) : people
            FlowLayout(spacing: 10) {
                ForEach(shown) { PlanName(duty: $0, short: true) }
                if people.count > 3 {
                    Text("+\(people.count - 2)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}

/// One person or group of a task: picture (or group icon), name and its state.
struct PlanName: View {
    let duty: Duty
    let short: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        let group = duty.planIsGroup
        let asked = duty.isRequested || duty.isDeclined
        let uid = asked ? duty.requestedUser : duty.assignedUser
        let full: String = {
            if group { return duty.groupName }
            if uid == store.user?.userId { return String(localized: "Du") }
            let name = asked ? duty.requestedUserName : duty.assignedUserName
            return name.isEmpty ? String(localized: "Person") : name
        }()
        let name = short && !group ? (full.split(separator: " ").first.map(String.init) ?? full) : full
        HStack(spacing: 5) {
            if group {
                Image(systemName: "person.3.fill").font(.system(size: 8)).foregroundStyle(Palette.indigo)
                    .frame(width: 18, height: 18)
                    .background(Palette.indigo.opacity(0.14), in: Circle())
            } else {
                Avatar(userId: uid.isEmpty ? nil : uid, name: full, size: 18)
            }
            Text(name).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(duty.isDeclined ? Palette.textSecondary : Palette.text)
                .lineLimit(1)
            if duty.isRequested {
                Text("angefragt").font(.system(size: 12.5)).italic().foregroundStyle(Palette.amberText)
            } else if duty.isDeclined {
                Text("abgelehnt").font(.system(size: 12.5)).italic().foregroundStyle(Palette.danger)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
