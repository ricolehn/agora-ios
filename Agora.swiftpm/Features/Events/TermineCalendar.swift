import SwiftUI

/// Category of an entry in the Termine calendar, in the order of its dots (same colours as the card stripes).
enum TerminCategory: CaseIterable, Hashable {
    case pinned, event, termin

    var color: Color {
        switch self {
        case .pinned: return Palette.indigo
        case .event: return Palette.primary
        case .termin: return Color(hex: 0x94A3B8)
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .pinned: return "Highlight"
        case .event: return "Event"
        case .termin: return "Termin"
        }
    }
}

extension AgoraEvent {
    var terminCategory: TerminCategory { isPinned ? .pinned : (isTermin ? .termin : .event) }
}

/// Month calendar next to the Termine list on iPad (like the web from 1024px and the Android tablet layout): a dot
/// per category on days with entries, today outlined, the chosen day filled; a tap on a day lets the list scroll
/// there. Past days are faded.
struct TermineCalendar: View {
    /// "2026-10"
    @Binding var month: String
    let days: [String: Set<TerminCategory>]
    let selected: String?
    let today: String
    let onDay: (String) -> Void

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Formats.locale
        calendar.firstWeekday = 2
        // Same time zone as Day.date / Day.string, so the first of the month keeps its weekday
        calendar.timeZone = .current
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                navButton("chevron.left", label: "Vorheriger Monat", enabled: month > Day.month(today)) { shift(-1) }
                Text(Formats.monthYear(month))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity)
                navButton("chevron.right", label: "Nächster Monat", enabled: true) { shift(1) }
            }
            .padding(.bottom, 12)
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { name in
                    Text(name.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            Hairline().padding(.top, 12)
            HStack(spacing: 14) {
                ForEach([TerminCategory.termin, .event, .pinned], id: \.self) { category in
                    HStack(spacing: 6) {
                        Circle().fill(category.color).frame(width: 7, height: 7)
                        Text(category.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .padding(.top, 12)
        }
        .card(padding: 18)
    }

    /// Short weekday names from Monday.
    private var weekdays: [String] {
        let symbols = calendar.shortWeekdaySymbols.map { $0.replacingOccurrences(of: ".", with: "") }
        return Array(symbols[1...] + symbols[..<1])
    }

    /// Days of the month ("yyyy-MM-dd") with empty cells before the first Monday.
    private var cells: [String?] {
        guard let first = Day.date(month + "-01"),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday + 5) % 7
        return Array(repeating: nil, count: lead) + range.map { String(format: "%@-%02d", month, $0) }
    }

    private func shift(_ months: Int) {
        guard let first = Day.date(month + "-01"), let next = calendar.date(byAdding: .month, value: months, to: first) else { return }
        withAnimation(.snappy) { month = Day.month(Day.string(next)) }
    }

    private func navButton(_ systemImage: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.text)
                .frame(width: 36, height: 36)
                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func cell(_ day: String) -> some View {
        let isPast = day < today
        let isSelected = day == selected
        let isToday = day == today
        let categories = days[day] ?? []
        let number = Int(day.suffix(2)) ?? 0
        return Button { onDay(day) } label: {
            VStack(spacing: 3) {
                Text("\(number)")
                    .font(.system(size: 15, weight: categories.isEmpty && !isToday ? .semibold : .heavy))
                    .foregroundStyle(isSelected ? .white : (isToday ? Palette.primary : (isPast ? Palette.textSecondary : Palette.text)))
                HStack(spacing: 3) {
                    ForEach(TerminCategory.allCases.filter { categories.contains($0) }, id: \.self) { category in
                        Circle().fill(isSelected ? .white : category.color).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.primary) }
            }
            .overlay {
                if isToday && !isSelected { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.primary, lineWidth: 2) }
            }
            .contentShape(Rectangle())
            .opacity(isPast ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isPast)
        .accessibilityLabel(Text(Formats.longDay(day)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
