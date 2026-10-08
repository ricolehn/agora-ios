import UIKit

/*
 * The financial report as PDF, drawn like the web's A4 page and the Android app: colour band, logo and app name,
 * kind and title with the period, three total cards, the bookings as a table with coloured kind pills and a
 * balance row (or, compact, one line per kind), a footer line. Measures are the web's CSS pixels of the 794px wide
 * page; the context is scaled to A4 points.
 */

/// One booking row of the report.
struct ReportRow: Hashable {
    var date: String
    var kind: String          // "pay", "don", "exp"
    var kindLabel: String
    var title: String
    var subtitle: String?
    var amount: String
    var income: Bool
    var note: String?
    var receipt = false
}

struct ReportStat: Hashable {
    var label: String
    var value: String
    var note: String?
    var color: UIColor
    var valueColor: UIColor
    var textValue = false
}

struct ReportKindLine: Hashable {
    var kind: String
    var label: String
    var count: String
    var amount: String
    var income: Bool
}

/// Everything the page shows, already formatted.
struct ReportContent: Hashable {
    var appName: String
    var logo: UIImage?
    var createdLabel: String
    var createdDate: String
    var kicker: String
    var title: String
    var period: String
    var stats: [ReportStat]
    var sectionTitle: String
    var compact: Bool
    var detailed: Bool
    /// date, kind, description, amount (compact: kind, count, amount)
    var headers: [String]
    var rows: [ReportRow]
    var kinds: [ReportKindLine]
    var balanceLabel: String
    var balance: String
    var balancePositive: Bool
    var receiptLabel: String
    var footerLeft: String
    var footerRight: String
}

enum ReportColors {
    static let green = UIColor(hex: 0x059669)
    static let red = UIColor(hex: 0xDC2626)
    static let navy = UIColor(hex: 0x0F172A)
    static let stripeIncome = UIColor(hex: 0x10B981)
    static let stripeExpense = UIColor(hex: 0xEF4444)
    static let stripeBalance = UIColor(hex: 0x0891B2)
    static let valueIncome = UIColor(hex: 0x10B981)
    static let valueExpense = UIColor(hex: 0xEF4444)
}

enum ReportPdf {
    private static let pageW: CGFloat = 794
    private static let pageH: CGFloat = 1123
    private static let side: CGFloat = 48
    private static let bottom: CGFloat = 60
    private static let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)

    private static let ink = UIColor(hex: 0x0F172A)
    private static let textColor = UIColor(hex: 0x334155)
    private static let muted = UIColor(hex: 0x64748B)
    private static let faint = UIColor(hex: 0x94A3B8)
    private static let line = UIColor(hex: 0xE2E8F0)
    private static let softLine = UIColor(hex: 0xEEF2F6)
    private static let surface = UIColor(hex: 0xF8FAFC)
    private static let headBg = UIColor(hex: 0xF1F5F9)
    private static let zebra = UIColor(hex: 0xFBFDFF)

    /// The report as PDF data (A4).
    static func data(_ content: ReportContent) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: a4, format: UIGraphicsPDFRendererFormat())
        return renderer.pdfData { context in
            let writer = PageWriter {
                context.beginPage()
                let cg = context.cgContext
                cg.scaleBy(x: a4.width / pageW, y: a4.width / pageW)
                return cg
            }
            draw(content, writer)
        }
    }

    // MARK: - Drawing helpers

    /// Pill colours per kind: text, background, border (like the web).
    private static func pillColors(_ kind: String) -> (UIColor, UIColor, UIColor) {
        switch kind {
        case "pay": return (UIColor(hex: 0x059669), UIColor(hex: 0xECFDF5), UIColor(hex: 0xA7F3D0))
        case "don": return (UIColor(hex: 0x7C3AED), UIColor(hex: 0xF5F3FF), UIColor(hex: 0xDDD6FE))
        default: return (UIColor(hex: 0xDC2626), UIColor(hex: 0xFEF2F2), UIColor(hex: 0xFECACA))
        }
    }

    private struct Style {
        var size: CGFloat
        var color: UIColor
        var weight: UIFont.Weight = .regular
        /// Letter spacing in em, like CSS.
        var spacing: CGFloat = 0

        var font: UIFont { UIFont.systemFont(ofSize: size, weight: weight) }

        func attributes(truncating: Bool) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = truncating ? .byTruncatingTail : .byClipping
            return [.font: font, .foregroundColor: color, .kern: spacing * size, .paragraphStyle: paragraph]
        }
    }

    private static func style(_ size: CGFloat, _ color: UIColor, bold: Bool = false, semibold: Bool = false, spacing: CGFloat = 0) -> Style {
        Style(size: size, color: color, weight: bold ? .heavy : (semibold ? .semibold : .regular), spacing: spacing)
    }

    private static func width(_ text: String, _ style: Style) -> CGFloat {
        ceil((text as NSString).size(withAttributes: style.attributes(truncating: false)).width)
    }

    /// Draws one line of text on a baseline, cut with "…" at [maxWidth].
    private static func text(_ text: String, x: CGFloat, baseline: CGFloat, _ style: Style, maxWidth: CGFloat? = nil, alignRight: Bool = false) {
        let font = style.font
        let full = width(text, style)
        let shown = min(full, maxWidth ?? full)
        let left = alignRight ? x - shown : x
        let rect = CGRect(x: left, y: baseline - font.ascender, width: shown + 1, height: font.lineHeight + 2)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: style.attributes(truncating: true), context: nil)
    }

    private static func fillRect(_ cg: CGContext, _ rect: CGRect, _ color: UIColor) {
        cg.setFillColor(color.cgColor)
        cg.fill(rect)
    }

    private static func roundRect(_ cg: CGContext, _ rect: CGRect, radius: CGFloat, fill: UIColor? = nil, stroke: UIColor? = nil, lineWidth: CGFloat = 1) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        if let fill {
            cg.addPath(path)
            cg.setFillColor(fill.cgColor)
            cg.fillPath()
        }
        if let stroke {
            // Stroke inside the rect, like Android's centred 1px line on a pixel grid
            cg.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), cornerRadius: radius).cgPath)
            cg.setStrokeColor(stroke.cgColor)
            cg.setLineWidth(lineWidth)
            cg.strokePath()
        }
    }

    private static func hLine(_ cg: CGContext, _ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat, _ color: UIColor, width: CGFloat = 1) {
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(width)
        cg.move(to: CGPoint(x: x1, y: y))
        cg.addLine(to: CGPoint(x: x2, y: y))
        cg.strokePath()
    }

    /// Where pages go. [start] begins a page and returns its context in CSS pixels of the web page.
    private final class PageWriter {
        private let start: () -> CGContext
        var cg: CGContext!
        var y: CGFloat = 0

        init(start: @escaping () -> CGContext) { self.start = start }

        func newPage() {
            cg = start()
            y = ReportPdf.side
        }

        func fits(_ height: CGFloat) -> Bool { y + height <= ReportPdf.pageH - ReportPdf.bottom }
    }

    // MARK: - Page

    private static func draw(_ content: ReportContent, _ w: PageWriter) {
        w.newPage()
        let c0 = w.cg!
        let right = pageW - side
        // Colour band across the top
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor(hex: 0x06B6D4).cgColor, UIColor(hex: 0x10B981).cgColor] as CFArray, locations: [0, 1]) {
            c0.saveGState()
            c0.clip(to: CGRect(x: 0, y: 0, width: pageW, height: 8))
            c0.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: pageW, y: 0), options: [])
            c0.restoreGState()
        }
        // Header: logo + app name, creation date on the right
        var y: CGFloat = 42
        var nameX = side
        if let logo = content.logo, logo.size.width > 0, logo.size.height > 0 {
            let size: CGFloat = 40
            let scale = min(size / logo.size.width, size / logo.size.height)
            let lw = logo.size.width * scale
            let lh = logo.size.height * scale
            logo.draw(in: CGRect(x: side, y: y + (size - lh) / 2, width: lw, height: lh))
            nameX = side + size + 12
        }
        text(content.appName, x: nameX, baseline: y + 27, style(20, UIColor(hex: 0x1E3A8A), bold: true), maxWidth: 420)
        text(content.createdLabel.uppercased(), x: right, baseline: y + 12, style(10, faint, bold: true, spacing: 0.08), alignRight: true)
        text(content.createdDate, x: right, baseline: y + 30, style(13, textColor, bold: true), alignRight: true)
        y += 58
        hLine(c0, side, right, y, line)
        y += 34
        // Kind, title, period
        text(content.kicker.uppercased(), x: side, baseline: y, style(11, UIColor(hex: 0x0891B2), bold: true, spacing: 0.1))
        y += 38
        text(content.title, x: side, baseline: y, style(30, ink, bold: true, spacing: -0.02))
        y += 24
        text(content.period, x: side, baseline: y, style(14, muted, semibold: true), maxWidth: right - side)
        y += 30
        // Three total cards
        let gap: CGFloat = 14
        let cardW = (right - side - gap * 2) / 3
        let cardH: CGFloat = 104
        for (i, stat) in content.stats.prefix(3).enumerated() {
            let x = side + CGFloat(i) * (cardW + gap)
            let rect = CGRect(x: x, y: y, width: cardW, height: cardH)
            roundRect(c0, rect, radius: 14, fill: surface)
            // Coloured stripe on the left edge, cut to the card's rounded corners
            c0.saveGState()
            c0.clip(to: CGRect(x: x, y: y, width: 4, height: cardH))
            roundRect(c0, rect, radius: 14, fill: stat.color)
            c0.restoreGState()
            roundRect(c0, rect, radius: 14, stroke: line)
            text(stat.label.uppercased(), x: x + 18, baseline: y + 30, style(10, muted, bold: true, spacing: 0.08), maxWidth: cardW - 30)
            text(stat.value, x: x + 18, baseline: y + 62, style(stat.textValue ? 17 : 22, stat.valueColor, bold: true), maxWidth: cardW - 30)
            if let note = stat.note { text(note, x: x + 18, baseline: y + 84, style(11, faint, semibold: true), maxWidth: cardW - 30) }
        }
        y += cardH + 30
        text(content.sectionTitle.uppercased(), x: side, baseline: y, style(11, muted, bold: true, spacing: 0.1))
        y += 12
        w.y = y

        // Table: columns like the web (date, kind, description, amount)
        let tableW = right - side
        let cols: [CGFloat] = content.compact ? [side + 14, side + tableW * 0.34] : [side + 14, side + 126, side + 242]
        let headerH: CGFloat = 36
        var tableTop = w.y

        func drawHeader() {
            let c = w.cg!
            tableTop = w.y
            fillRect(c, CGRect(x: side, y: w.y, width: tableW, height: headerH), headBg)
            hLine(c, side, right, w.y + headerH, line)
            let head = style(10, muted, bold: true, spacing: 0.08)
            for (i, title) in content.headers.dropLast().enumerated() where i < cols.count {
                text(title.uppercased(), x: cols[i], baseline: w.y + 23, head)
            }
            text((content.headers.last ?? "").uppercased(), x: right - 14, baseline: w.y + 23, head, alignRight: true)
            w.y += headerH
        }
        func closeTable() {
            // Frame around the part of the table on this page
            roundRect(w.cg, CGRect(x: side, y: tableTop, width: tableW, height: w.y - tableTop), radius: 12, stroke: line)
        }
        func pill(_ c: CGContext, kind: String, label: String, x: CGFloat, top: CGFloat) {
            let (fg, bg, border) = pillColors(kind)
            let s = style(11, fg, bold: true)
            let rect = CGRect(x: x, y: top, width: width(label, s) + 18, height: 20)
            roundRect(c, rect, radius: 10, fill: bg, stroke: border)
            text(label, x: x + 9, baseline: top + 14, s)
        }

        drawHeader()
        if content.compact {
            for (i, kindLine) in content.kinds.enumerated() {
                let h: CGFloat = 44
                if !w.fits(h) { closeTable(); w.newPage(); drawHeader() }
                let c = w.cg!
                if i % 2 == 1 { fillRect(c, CGRect(x: side, y: w.y, width: tableW, height: h), zebra) }
                pill(c, kind: kindLine.kind, label: kindLine.label, x: cols[0], top: w.y + 12)
                text(kindLine.count, x: cols[1], baseline: w.y + 27, style(12.5, muted))
                text(kindLine.amount, x: right - 14, baseline: w.y + 27, style(12.5, kindLine.income ? ReportColors.green : ReportColors.red, bold: true), alignRight: true)
                if i < content.kinds.count - 1 { hLine(c, side, right, w.y + h, softLine) }
                w.y += h
            }
            closeTable()
        } else {
            let descW = right - 14 - cols[2] - 110
            for (i, row) in content.rows.enumerated() {
                let details = content.detailed && (row.note != nil || row.receipt)
                let detailH: CGFloat = details ? (row.note != nil ? 18 : 0) + (row.receipt ? 18 : 0) + 6 : 0
                let h: CGFloat = (row.subtitle != nil ? 56 : 44) + detailH
                if !w.fits(h + 44) { closeTable(); w.newPage(); drawHeader() }
                let c = w.cg!
                if i % 2 == 1 { fillRect(c, CGRect(x: side, y: w.y, width: tableW, height: h), zebra) }
                text(row.date, x: cols[0], baseline: w.y + 25, style(12.5, muted))
                pill(c, kind: row.kind, label: row.kindLabel, x: cols[1], top: w.y + 10)
                text(row.title, x: cols[2], baseline: w.y + 25, style(12.5, ink, semibold: true), maxWidth: descW)
                var lineY = w.y + 25
                if let subtitle = row.subtitle {
                    lineY += 16
                    text(subtitle, x: cols[2], baseline: lineY, style(11, faint), maxWidth: descW)
                }
                text(row.amount, x: right - 14, baseline: w.y + 25, style(12.5, row.income ? ReportColors.green : ReportColors.red, bold: true), alignRight: true)
                if details {
                    if let note = row.note {
                        lineY += 18
                        text("„\(note)“", x: cols[1], baseline: lineY, style(11.5, muted), maxWidth: right - 14 - cols[1])
                    }
                    if row.receipt {
                        lineY += 18
                        text("📎 \(content.receiptLabel)", x: cols[1], baseline: lineY, style(11, ReportColors.stripeBalance, semibold: true))
                    }
                }
                hLine(c, side, right, w.y + h, softLine)
                w.y += h
            }
            // Balance row
            let c = w.cg!
            fillRect(c, CGRect(x: side, y: w.y, width: tableW, height: 44), surface)
            hLine(c, side, right, w.y, line, width: 1.5)
            text(content.balanceLabel, x: cols[0], baseline: w.y + 27, style(13, ink, bold: true))
            text(content.balance, x: right - 14, baseline: w.y + 27, style(13, content.balancePositive ? ReportColors.green : ReportColors.red, bold: true), alignRight: true)
            w.y += 44
            closeTable()
        }
        // Footer line
        if !w.fits(52) { w.newPage() }
        w.y += 28
        hLine(w.cg, side, right, w.y, line)
        text(content.footerLeft, x: side, baseline: w.y + 22, style(10.5, faint), maxWidth: tableW / 2)
        text(content.footerRight, x: right, baseline: w.y + 22, style(10.5, faint), maxWidth: tableW / 2, alignRight: true)
    }
}
