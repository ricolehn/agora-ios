import SwiftUI

/// Treasury for finance managers: open requests, balance and history ("Übersicht"), member fees ("Beitragsliste").
struct TreasurerView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var model = TreasuryModel()
    @State private var tab: Tab = .overview
    @State private var entrySheet: FinanceEntrySheet.Kind?
    @State private var openRequest: FinanceRequest?
    @State private var reportOpen = false

    enum Tab: Hashable { case overview, members }

    private var canManage: Bool { store.user.map { $0.managesFinances || $0.owner } ?? false }

    var body: some View {
        TabPage(refresh: { await model.load(store) }) {
            PageTitle("Finanzen")
            PillTabs(items: [
                .init(value: Tab.overview, title: "Übersicht", systemImage: "clock"),
                .init(value: Tab.members, title: "Beitragsliste", systemImage: "person.2")
            ], selection: $tab)
            if model.loading && !model.loaded {
                LoadingCard()
            } else if let error = model.error, !model.loaded {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(Palette.danger).multilineTextAlignment(.center)
                    Button("Erneut versuchen") { Task { await model.load(store) } }.buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                }
                .card()
            } else if tab == .overview {
                overview
            } else {
                MemberListSection(model: model, canManage: canManage)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if canManage {
                FloatingAddButton(accessibility: "Buchung erfassen") {
                    Button { entrySheet = .donation } label: { Label("Spende erfassen", systemImage: "gift") }
                    Button { entrySheet = .expense } label: { Label("Ausgabe buchen", systemImage: "eurosign.circle") }
                }
            }
        }
        .sheet(item: $entrySheet) { kind in
            FinanceEntrySheet(kind: kind) { Task { await model.load(store) } }
        }
        .sheet(item: $openRequest) { request in
            RequestDetailSheet(request: request, canDecide: canManage) { Task { await model.load(store) } }
        }
        .sheet(isPresented: $reportOpen) { ReportSheet(people: model.people) }
        .task { if !model.loaded { await model.load(store) } }
        .onChange(of: store.changeTick) { _, _ in
            if store.changedAreas.contains("all") { Task { await model.load(store) } }
        }
    }

    @ViewBuilder
    private var overview: some View {
        // Same order as the web: open requests, balance, history
        if !model.pendingRequests.isEmpty {
            OpenRequestsCard(requests: model.pendingRequests) { openRequest = $0 }
        }
        VStack(spacing: 8) {
            Text("Aktueller Kassenstand")
                .font(.system(size: 12, weight: .bold)).textCase(.uppercase).tracking(0.6)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.black.opacity(0.15), in: Capsule())
            Text(Formats.money(model.stats.totalBalance)).font(.system(size: 40, weight: .heavy)).minimumScaleFactor(0.5).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Palette.brand, in: RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        .shadow(color: Color(hex: 0x06B6D4, opacity: 0.25), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        HStack {
            Text("Historie").font(.agoraSection).foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            // Financial report as PDF (like the web's "Bericht erstellen")
            Button { reportOpen = true } label: { Label("Bericht erstellen", systemImage: "doc.text") }
                .buttonStyle(.agoraSecondary(small: true, fullWidth: false))
        }
        .padding(.top, 4)
        SearchField(placeholder: "Historie durchsuchen…", text: $model.search)
            .onChange(of: model.search) { _, _ in model.searchChanged(store) }
        TransactionList(model: model)
    }
}

/// Treasury data loaded side by side; the search reloads only the history (debounced).
@MainActor
@Observable
final class TreasuryModel {
    var stats = FinanceStats()
    var pendingRequests: [FinanceRequest] = []
    var people: [Person] = []
    var transactions: [Transaction] = []
    var page = 1
    var totalPages = 1
    var search = ""
    var loading = false
    var loadingMore = false
    var loaded = false
    var error: String?
    var details: [String: Person] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    func load(_ store: AppStore) async {
        loading = true
        defer { loading = false }
        let repo = store.repository
        let query = search
        async let stats = repo.stats()
        async let requests = repo.allRequests()
        async let people = repo.allPeople()
        async let page = repo.transactions(page: 1, search: query)
        do {
            let (s, r, p, t) = try await (stats, requests, people, page)
            self.stats = s
            pendingRequests = r.filter(\.isPending)
            self.people = p
            transactions = t.items
            self.page = 1
            totalPages = max(t.totalPages, 1)
            details = [:]
            loaded = true
            error = nil
        } catch {
            self.error = APIError.text(error)
        }
    }

    func searchChanged(_ store: AppStore) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            if let result = try? await store.repository.transactions(page: 1, search: search) {
                transactions = result.items
                page = 1
                totalPages = max(result.totalPages, 1)
            }
        }
    }

    func loadMore(_ store: AppStore) async {
        guard !loadingMore, page < totalPages else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let result = try? await store.repository.transactions(page: page + 1, search: search) {
            transactions += result.items
            page += 1
            totalPages = max(result.totalPages, 1)
        }
    }

    func detail(_ store: AppStore, _ id: String) async {
        if let person = try? await store.repository.person(id: id) { details[id] = person }
    }
}

// MARK: - Requests

/// Thumbnails of receipts; tap opens them full screen.
struct ReceiptStrip: View {
    @Environment(AppStore.self) private var store
    let files: [String]
    @State private var shown: URL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files, id: \.self) { file in
                    if let url = store.repository.receiptURL(file) {
                        Button { shown = url } label: {
                            RemoteImage(url: url) {
                                Image(systemName: file.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "paperclip")
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .frame(width: 64, height: 64)
                            .background(Palette.surfaceAlt)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .accessibilityLabel("Beleg öffnen")
                    }
                }
            }
        }
        .sheet(item: Binding(get: { shown.map(IdentifiedURL.init) }, set: { shown = $0?.url })) { item in
            ReceiptViewer(url: item.url)
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Full-screen receipt: image zoomable, other files via the browser.
struct ReceiptViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            RemoteImage(url: url, contentMode: .fit) {
                VStack(spacing: 12) {
                    ProgressView()
                    Button("Im Browser öffnen") { openURL(url) }
                }
            }
            .scaleEffect(scale)
            .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Beleg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { ShareLink(item: url) }
            }
        }
    }
}

// MARK: - History

struct TransactionList: View {
    @Environment(AppStore.self) private var store
    let model: TreasuryModel
    @State private var selected: Transaction?

    var body: some View {
        Group { content }
            .sheet(item: $selected) { TransactionSheet(transaction: $0) }
    }

    @ViewBuilder
    private var content: some View {
        if model.transactions.isEmpty {
            EmptyState(systemImage: "list.bullet.rectangle", title: "Keine Buchungen gefunden").card(padding: 0)
        } else {
            let days = EventRules.byMonth(model.transactions, day: { $0.date })
            // Expenses show the issuer's picture: their account from the member records by name (like the web)
            let uidByName = Dictionary(model.people.filter { !$0.uid.isEmpty }.map { ($0.name.trimmingCharacters(in: .whitespaces).lowercased(), $0.uid) },
                                       uniquingKeysWith: { first, _ in first })
            ForEach(days, id: \.month) { group in
                SectionHeader(title: Formats.monthYear(group.month))
                ForEach(group.items) { transaction in
                    let avatar = transaction.type == "pay" ? transaction.personUid
                        : (transaction.type == "exp" ? uidByName[transaction.who.trimmingCharacters(in: .whitespaces).lowercased()] : nil)
                    Button { selected = transaction } label: { TransactionRow(transaction: transaction, avatarUserId: avatar) }
                        .buttonStyle(.pressable)
                }
            }
            if model.page < model.totalPages {
                Button { Task { await model.loadMore(store) } } label: {
                    BusyLabel(title: "Mehr laden…", busy: model.loadingMore)
                }
                .buttonStyle(.agoraSecondary)
            }
        }
    }
}

extension Transaction {
    var kindIcon: String { type == "don" ? "heart.fill" : (type == "exp" ? "eurosign" : "person.fill") }
    var kindColor: Color { type == "don" ? Color(hex: 0x8B5CF6) : (type == "exp" ? Palette.danger : Palette.success) }
    var kindLabel: LocalizedStringKey { type == "don" ? "Spende" : (type == "exp" ? "Ausgabe" : "Mitgliedsbeitrag") }
}

/// History row like the web: payments and expenses show the person's picture (initials without one; expenses with
/// a small red € badge), donations the purple tile; who, description, signed amount.
struct TransactionRow: View {
    let transaction: Transaction
    var avatarUserId: String?

    var body: some View {
        HStack(spacing: 12) {
            if transaction.type != "don" && !transaction.who.trimmingCharacters(in: .whitespaces).isEmpty {
                Avatar(userId: avatarUserId, name: transaction.who, size: 40)
                    .overlay(alignment: .bottomTrailing) {
                        if transaction.type == "exp" {
                            Image(systemName: "eurosign")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Palette.danger, in: Circle())
                                .padding(2)
                                .background(Palette.surface, in: Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
            } else {
                Image(systemName: transaction.kindIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(transaction.kindColor)
                    .frame(width: 40, height: 40)
                    .background(transaction.kindColor.opacity(0.15), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.who.isEmpty ? "–" : transaction.who).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    if !transaction.receipts.isEmpty { Image(systemName: "paperclip").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.primary) }
                }
                Text(transaction.description.isEmpty ? Formats.shortDay(transaction.date) : "\(Formats.shortDay(transaction.date)) · \(transaction.description)")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Formats.signedMoney(transaction.amount, income: transaction.isIncome))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(transaction.isIncome ? Palette.success : Palette.danger)
                .monospacedDigit()
        }
        .card(radius: Radius.list, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct TransactionSheet: View {
    let transaction: Transaction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text(Formats.signedMoney(transaction.amount, income: transaction.isIncome))
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(transaction.isIncome ? Palette.success : Palette.danger)
                        Text(transaction.kindLabel).font(.subheadline).foregroundStyle(Palette.textSecondary)
                        if transaction.isAuto { StatusPill(text: String(localized: "Dauerauftrag"), color: Palette.primary, systemImage: "repeat") }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Datum", value: Formats.longDay(transaction.date))
                    if !transaction.description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Beschreibung").font(.caption).foregroundStyle(Palette.textSecondary)
                            Text(transaction.description)
                        }
                    }
                }
                if !transaction.receipts.isEmpty {
                    Section("Belege") { ReceiptStrip(files: transaction.receipts) }
                }
            }
            .navigationTitle(transaction.who.isEmpty ? "Buchung" : transaction.who)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Member list

struct MemberListSection: View {
    @Environment(AppStore.self) private var store
    let model: TreasuryModel
    let canManage: Bool
    @State private var filter = ""
    @State private var expanded: String?

    var body: some View {
        let paying = model.people.filter { $0.pays && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)) }
        let overdue = paying.filter(\.statusMeta.isOverdue)
        let current = paying.filter { !$0.statusMeta.isOverdue }
        Text("Personen").font(.agoraSection).foregroundStyle(Palette.text)
        SearchField(placeholder: "Mitglieder suchen…", text: $filter)
        if paying.isEmpty {
            EmptyState(systemImage: "person.2", title: "Keine zahlenden Mitglieder gefunden").card(padding: 0)
        }
        if !overdue.isEmpty {
            SectionHeader(title: String(localized: "Überfällig"), count: overdue.count, color: Palette.danger)
            ForEach(overdue) { person in card(person) }
        }
        if !current.isEmpty {
            SectionHeader(title: String(localized: "Aktuelle Mitglieder"), count: current.count, color: Palette.success)
            ForEach(current) { person in card(person) }
        }
    }

    private func card(_ person: Person) -> some View {
        PersonCard(person: person, detail: model.details[person.id], expanded: expanded == person.id, canManage: canManage) {
            withAnimation(.snappy) { expanded = expanded == person.id ? nil : person.id }
            if model.details[person.id] == nil { Task { await model.detail(store, person.id) } }
        } onChanged: {
            Task {
                await model.load(store)
                await model.detail(store, person.id)
            }
        }
    }
}

/// Expandable member: status, paid-until, open amount; inside standing orders, actions and the timeline.
struct PersonCard: View {
    let person: Person
    let detail: Person?
    let expanded: Bool
    let canManage: Bool
    let toggle: () -> Void
    let onChanged: () -> Void
    @State private var sheet: PersonSheet?

    enum PersonSheet: Identifiable {
        case payment, status, order(StandingOrder)
        var id: String {
            switch self {
            case .payment: return "payment"
            case .status: return "status"
            case .order(let order): return "order-\(order.id)"
            }
        }
    }

    var body: some View {
        let shown = detail ?? person
        let color = person.stateColor
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(person.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(expanded ? Palette.primary : Palette.textSecondary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        CapsLabel(LocalizedStringKey(MemberStatus.name(person.effectiveStatus)))
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        if !person.standingOrderCovers {
                            Text(Formats.paidUntilMonth(person.paidUntil) ?? String(localized: "Nie"))
                                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(color, in: Capsule())
                        }
                        if !person.statusMeta.text.isEmpty {
                            Text(person.statusMeta.text).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Zuklappen" : "Aufklappen")
            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    summary(shown, color: color)
                    if !shown.standingOrders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel("Daueraufträge")
                            ForEach(shown.standingOrders) { order in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(Formats.money(order.amount)) / Monat").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                                        Text([order.endDate.map { "seit \(Formats.shortDay(order.startDate)) – \(Formats.shortDay($0))" } ?? "seit \(Formats.shortDay(order.startDate))",
                                              order.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
                                    }
                                    Spacer()
                                    if order.isActive(on: Day.today()) { StatusPill(text: String(localized: "Aktiv"), color: Palette.success) }
                                    if canManage {
                                        Button("Verwalten") { sheet = .order(order) }.font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .padding(12)
                                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            }
                        }
                    }
                    if canManage {
                        Button { sheet = .payment } label: { Label("Zahlung erfassen", systemImage: "plus") }.buttonStyle(.agoraPrimary)
                        Button { sheet = .status } label: { Label("Status", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.agoraSecondary)
                    }
                    CapsLabel("Verlauf")
                    if detail == nil { ProgressView().frame(maxWidth: .infinity) } else { FinanceTimeline(person: shown, plainStatus: true) }
                }
                .padding([.horizontal, .bottom], 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.list, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.list, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 6, y: 3)
        .sheet(item: $sheet) { which in
            switch which {
            case .payment: BookPaymentSheet(person: shown, onDone: onChanged)
            case .status: ChangeStatusSheet(person: shown, onDone: onChanged)
            case .order(let order): ManageStandingOrderSheet(person: shown, order: order, onDone: onChanged)
            }
        }
    }

    private func summary(_ person: Person, color: Color) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel("Status")
                    Text(MemberStatus.name(person.effectiveStatus)).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel("Bezahlt bis")
                    if person.standingOrderCovers {
                        StatusPill(text: String(localized: "Dauerauftrag läuft"), color: Palette.success, systemImage: "repeat")
                    } else {
                        Text(Formats.paidUntilMonth(person.paidUntil) ?? String(localized: "Nie")).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if person.statusMeta.isOverdue && person.overdueAmount > 0 {
                HStack {
                    Text("Offener Betrag").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(Formats.money(person.overdueAmount)).font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(Palette.danger)
                .padding(10)
                .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.nested, style: .continuous))
    }
}
