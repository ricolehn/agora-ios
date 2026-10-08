import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import WebKit

/// Financial report (like the web and Android): kind of report as four cards, period / member / bookings, level of
/// detail; the preview is the real first page of the PDF, which can be shared or saved to Files.
struct ReportSheet: View {
    let people: [Person]
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var transactions: [Transaction]?
    @State private var loadError = false
    @State private var logo: UIImage?
    @State private var type: ReportType = .annual
    @State private var tier: ReportTier = .standard
    @State private var year = String(Day.today().prefix(4))
    @State private var from = String(Day.today().prefix(4)) + "-01-01"
    @State private var to = Day.today()
    @State private var personId = ""
    @State private var selected: Set<String> = []
    @State private var preview: UIImage?
    @State private var pages = 0
    @State private var pdf: Data?
    @State private var fileURL: URL?
    @State private var exporting = false

    enum ReportType: CaseIterable, Hashable {
        case annual, custom, person, manual

        var systemImage: String {
            switch self {
            case .annual: return "calendar"
            case .custom: return "clock"
            case .person: return "person"
            case .manual: return "checklist"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .annual: return "Jahresübersicht"
            case .custom: return "Zeitraum"
            case .person: return "Einzelperson"
            case .manual: return "Auswahl"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .annual: return "Ein ganzes Jahr"
            case .custom: return "Von – bis"
            case .person: return "Beiträge eines Mitglieds"
            case .manual: return "Buchungen ankreuzen"
            }
        }

        var kicker: String {
            switch self {
            case .annual: return String(localized: "Jahresübersicht")
            case .custom: return String(localized: "Übersicht für einen Zeitraum")
            case .person: return String(localized: "Übersicht für ein Mitglied")
            case .manual: return String(localized: "Ausgewählte Buchungen")
            }
        }
    }

    enum ReportTier: CaseIterable, Hashable {
        case compact, standard, detailed

        var title: LocalizedStringKey {
            switch self {
            case .compact: return "Kompakt"
            case .standard: return "Standard"
            case .detailed: return "Ausführlich"
            }
        }

        var hint: LocalizedStringKey {
            switch self {
            case .compact: return "Nur Summen und eine Aufstellung nach Art"
            case .standard: return "Summen und alle Buchungen"
            case .detailed: return "Zusätzlich Notizen und Belege"
            }
        }
    }

    // MARK: - Data

    private var sortedPeople: [Person] { people.sorted { $0.name.lowercased() < $1.name.lowercased() } }
    private var person: Person? { sortedPeople.first { $0.id == personId } ?? sortedPeople.first }
    private var all: [Transaction] { transactions ?? [] }
    private var today: String { Day.today() }

    private var years: [String] {
        let found = all.compactMap { tx -> String? in
            let y = String(tx.date.prefix(4))
            return y.count == 4 ? y : nil
        }
        return Array(Set(found + [String(today.prefix(4))])).sorted(by: >)
    }

    private static func key(_ tx: Transaction) -> String { "\(tx.type)-\(tx.id)-\(tx.date)" }
    private static func kind(_ tx: Transaction) -> String { tx.type == "exp" ? "exp" : (tx.type.isEmpty ? "pay" : tx.type) }

    private func inRange(_ tx: Transaction) -> Bool {
        let day = String(tx.date.prefix(10))
        return (from.isEmpty || day >= from) && (to.isEmpty || day <= to)
    }

    private var filtered: [Transaction] {
        let list: [Transaction]
        switch type {
        case .annual: list = all.filter { $0.date.hasPrefix(year) }
        case .custom: list = all.filter(inRange)
        case .manual: list = all.filter { selected.contains(Self.key($0)) }
        case .person:
            guard let person else { return [] }
            list = all.filter { tx in
                let byId = tx.personId == person.id || (!(tx.personUid ?? "").isEmpty && tx.personUid == person.uid)
                let byName = tx.who.trimmingCharacters(in: .whitespaces).lowercased() == person.name.trimmingCharacters(in: .whitespaces).lowercased()
                return (byId || byName) && inRange(tx)
            }
        }
        return list.sorted { $0.date < $1.date }
    }

    /// dd.MM.yyyy (German) / dd/MM/yyyy (otherwise), like the web report.
    private static func reportDate(_ iso: String) -> String {
        guard iso.count >= 10 else { return iso }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return iso }
        let separator = Formats.isGerman ? "." : "/"
        return [parts[2], parts[1], parts[0]].joined(separator: separator)
    }

    private static func signed(_ amount: Double, _ income: Bool) -> String { (income ? "+" : "-") + Formats.money(abs(amount)) }

    private static func bookings(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Buchung") : String(localized: "\(count) Buchungen")
    }

    private var periodText: String {
        switch type {
        case .annual: return String(localized: "Jahr: \(year)")
        case .manual: return String(localized: "Manuelle Auswahl")
        case .custom:
            return from.isEmpty && to.isEmpty ? String(localized: "Alle Buchungen") : "\(Self.reportDate(from)) - \(Self.reportDate(to))"
        case .person: return "\(person?.name ?? ""): \(Self.reportDate(from)) - \(Self.reportDate(to))"
        }
    }

    private var net: Double {
        filtered.reduce(0) { $0 + ($1.type == "exp" ? -$1.amount : $1.amount) }
    }

    private var content: ReportContent {
        let items = filtered
        let income = items.filter { $0.type != "exp" }
        let expenses = items.filter { $0.type == "exp" }
        let net = self.net
        let kindLabels = ["pay": String(localized: "Beitrag"), "don": String(localized: "Spende"), "exp": String(localized: "Ausgabe")]
        let overdue = person?.overdueAmount ?? 0
        let third: ReportStat
        if type != .person {
            third = ReportStat(label: String(localized: "Saldo"), value: Self.signed(net, net >= 0), note: Self.bookings(items.count),
                               color: ReportColors.stripeBalance, valueColor: ReportColors.navy)
        } else if overdue > 0 {
            third = ReportStat(label: String(localized: "Ausstehend (bis heute)"), value: Formats.money(overdue), note: nil,
                               color: ReportColors.stripeExpense, valueColor: ReportColors.valueExpense)
        } else {
            third = ReportStat(label: String(localized: "Status"), value: String(localized: "Kein Rückstand"), note: nil,
                               color: ReportColors.stripeIncome, valueColor: ReportColors.valueIncome, textValue: true)
        }
        let stats = [
            ReportStat(label: String(localized: "Einnahmen"), value: "+" + Formats.money(income.reduce(0) { $0 + $1.amount }),
                       note: Self.bookings(income.count), color: ReportColors.stripeIncome, valueColor: ReportColors.valueIncome),
            ReportStat(label: String(localized: "Ausgaben"), value: "-" + Formats.money(expenses.reduce(0) { $0 + $1.amount }),
                       note: Self.bookings(expenses.count), color: ReportColors.stripeExpense, valueColor: ReportColors.valueExpense),
            third
        ]
        let kinds: [ReportKindLine] = ["pay", "don", "exp"].compactMap { kind in
            let group = items.filter { Self.kind($0) == kind }
            guard !group.isEmpty else { return nil }
            return ReportKindLine(kind: kind, label: kindLabels[kind] ?? kind, count: Self.bookings(group.count),
                                  amount: Self.signed(group.reduce(0) { $0 + $1.amount }, kind != "exp"), income: kind != "exp")
        }
        let rows = items.map { tx -> ReportRow in
            let kind = Self.kind(tx)
            let label = kindLabels[kind] ?? kindLabels["exp"] ?? ""
            let title: String
            switch kind {
            case "pay": title = tx.who
            case "don": title = tx.who.isEmpty ? label : tx.who
            default: title = !tx.description.isEmpty ? tx.description : (tx.who.isEmpty ? label : tx.who)
            }
            let subtitle = kind == "exp" && !tx.description.isEmpty && !tx.who.isEmpty && tx.who != tx.description ? tx.who : nil
            return ReportRow(date: Self.reportDate(tx.date), kind: kind, kindLabel: label, title: title, subtitle: subtitle,
                             amount: Self.signed(tx.amount, tx.type != "exp"), income: tx.type != "exp",
                             note: kind != "exp" && !tx.description.isEmpty ? tx.description : nil,
                             receipt: !(tx.receipt ?? "").isEmpty)
        }
        let reportTitle = String(localized: "Finanzbericht")
        return ReportContent(
            appName: store.appName, logo: logo,
            createdLabel: String(localized: "Erstellt am"), createdDate: Self.reportDate(today),
            kicker: type.kicker, title: reportTitle, period: periodText, stats: stats,
            sectionTitle: tier == .compact ? String(localized: "Nach Art") : String(localized: "Buchungen"),
            compact: tier == .compact, detailed: tier == .detailed,
            headers: tier == .compact
                ? [String(localized: "Art"), String(localized: "Anzahl"), String(localized: "Betrag")]
                : [String(localized: "Datum"), String(localized: "Art"), String(localized: "Beschreibung / Partner"), String(localized: "Betrag")],
            rows: rows, kinds: kinds,
            balanceLabel: String(localized: "Saldo"), balance: Self.signed(net, net >= 0), balancePositive: net >= 0,
            receiptLabel: String(localized: "Beleg vorhanden"),
            footerLeft: "\(store.appName) · \(reportTitle)", footerRight: periodText)
    }

    private var fileName: String {
        let safe = String(store.appName.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        return "\(safe)_\(String(localized: "Finanzbericht"))_\(today).pdf"
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CapsLabel("Berichtstyp")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(ReportType.allCases, id: \.self) { option in typeCard(option) }
                    }
                    options
                    CapsLabel("Detailgrad").padding(.top, 6)
                    Picker("Detailgrad", selection: $tier) {
                        ForEach(ReportTier.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(tier.hint).font(.footnote).foregroundStyle(Palette.textSecondary)
                    HStack {
                        CapsLabel("Vorschau")
                        Spacer()
                        if pages > 0 {
                            Text(pages == 1 ? String(localized: "1 Seite") : String(localized: "\(pages) Seiten"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.top, 6)
                    previewBox
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Finanzbericht erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { actions }
        }
        .task { await load() }
        .task(id: content) { await render() }
        .fileExporter(isPresented: $exporting, document: PDFFile(data: pdf ?? Data()), contentType: .pdf, defaultFilename: fileName) { result in
            switch result {
            case .success: toasts.show(String(localized: "Bericht gespeichert"))
            case .failure: toasts.show(String(localized: "Etwas ist schiefgelaufen."), error: true)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch type {
        case .annual:
            CapsLabel("Jahr").padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(years, id: \.self) { option in
                        let active = option == year
                        Button { year = option } label: {
                            Text(option)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(active ? .white : Palette.text)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(active ? Palette.primary : Palette.surfaceAlt, in: Capsule())
                                .overlay(Capsule().strokeBorder(active ? Palette.primary : Palette.borderLight, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .custom:
            dateRange
        case .person:
            if !sortedPeople.isEmpty {
                HStack {
                    Text("Mitglied").foregroundStyle(Palette.text)
                    Spacer()
                    Picker("Mitglied", selection: Binding(get: { person?.id ?? "" }, set: { personId = $0 })) {
                        ForEach(sortedPeople) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .card(radius: Radius.nested, padding: nil)
            }
            dateRange
        case .manual:
            CapsLabel("Buchungen auswählen").padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(all.sorted { $0.date > $1.date }.enumerated()), id: \.offset) { index, tx in
                    if index > 0 { Hairline() }
                    manualRow(tx)
                }
            }
            .card(radius: Radius.nested, padding: nil)
        }
    }

    private var dateRange: some View {
        VStack(spacing: 0) {
            DayPicker(title: "Von", day: $from).padding(.vertical, 6)
            Hairline()
            DayPicker(title: "Bis", day: $to).padding(.vertical, 6)
        }
        .padding(.horizontal, 14)
        .card(radius: Radius.nested, padding: nil)
    }

    private func manualRow(_ tx: Transaction) -> some View {
        let key = Self.key(tx)
        let checked = selected.contains(key)
        return Button {
            if checked { selected.remove(key) } else { selected.insert(key) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(checked ? Palette.primary : Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.who.isEmpty ? tx.description : tx.who)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(Self.reportDate(tx.date)).font(.footnote).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 8)
                Text(Self.signed(tx.amount, tx.type != "exp"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tx.type == "exp" ? Palette.danger : Palette.success)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private func typeCard(_ option: ReportType) -> some View {
        let active = option == type
        return Button { withAnimation(.snappy) { type = option } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? .white : Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(active ? Palette.primary : Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 4)
                Text(option.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(option.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(active ? Palette.primary.opacity(0.07) : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? Palette.primary : Palette.borderLight, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var previewBox: some View {
        ZStack {
            Color.white
            if transactions == nil && !loadError {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Lade Buchungen…").font(.footnote).foregroundStyle(Color(hex: 0x64748B))
                }
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 34)).foregroundStyle(Color(hex: 0xCBD5E1))
                    Text(type == .manual ? "Kreuze die Buchungen an, die in den Bericht sollen."
                         : (loadError ? "Etwas ist schiefgelaufen." : "Keine Daten im gewählten Zeitraum"))
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: 0x94A3B8))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else if let preview {
                Image(uiImage: preview).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .aspectRatio(595.0 / 842.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
    }

    private var actions: some View {
        let ready = !filtered.isEmpty && pdf != nil
        return VStack(spacing: 8) {
            if !filtered.isEmpty {
                Text("\(Self.bookings(filtered.count)) · \(String(localized: "Saldo")) \(Self.signed(net, net >= 0))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 10) {
                if let fileURL, ready {
                    ShareLink(item: fileURL, preview: SharePreview(fileName, image: Image(systemName: "doc.richtext"))) {
                        Label("Teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button {} label: { Label("Teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(true)
                }
                Button { exporting = true } label: {
                    Label("PDF speichern", systemImage: "arrow.down.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!ready)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Work

    @MainActor
    private func load() async {
        if personId.isEmpty { personId = sortedPeople.first?.id ?? "" }
        do {
            transactions = try await store.repository.allTransactions()
        } catch {
            loadError = true
        }
        logo = await ReportLogo.image(store)
    }

    /// The preview is the real first page of the PDF.
    @MainActor
    private func render() async {
        guard transactions != nil, !filtered.isEmpty else {
            preview = nil
            pages = 0
            pdf = nil
            return
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        let data = ReportPdf.data(content)
        pdf = data
        if let document = PDFDocument(data: data) {
            pages = document.pageCount
            preview = document.page(at: 0)?.thumbnail(of: CGSize(width: 1000, height: 1415), for: .mediaBox)
        }
        // File for sharing (one at a time in the temp folder)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        fileURL = (try? data.write(to: url)) != nil ? url : nil
    }
}

/// PDF for the "Save to Files" dialog.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// The church logo of the server (its SVG drawn offscreen), else the app's own mark.
@MainActor
enum ReportLogo {
    static func image(_ store: AppStore) async -> UIImage? {
        if let svg = await LogoCache.shared.svg(store), let image = await SVGSnapshot().render(svg, size: 160) { return image }
        let renderer = ImageRenderer(content: AppMark(size: 80))
        renderer.scale = 2
        return renderer.uiImage
    }
}

/// Draws an SVG in an offscreen web view and takes a picture of it.
@MainActor
private final class SVGSnapshot: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func render(_ svg: String, size: CGFloat) async -> UIImage? {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = self
        // A web view outside a window often snapshots blank: add it invisibly while it draws
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        window?.addSubview(view)
        defer { view.removeFromSuperview() }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;width:100%;height:100%;background:transparent;overflow:hidden}
        svg{display:block;width:100%;height:100%}</style></head><body>
        """ + svg + "</body></html>"
        let loaded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.continuation = continuation
            view.loadHTMLString(html, baseURL: nil)
            // Give up after a few seconds
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self.finish(false)
            }
        }
        guard loaded else { return nil }
        try? await Task.sleep(nanoseconds: 150_000_000)
        let config = WKSnapshotConfiguration()
        config.rect = view.bounds
        config.afterScreenUpdates = true
        return try? await view.takeSnapshot(configuration: config)
    }

    private func finish(_ ok: Bool) {
        continuation?.resume(returning: ok)
        continuation = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish(true) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(false) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(false) }
    }
}
