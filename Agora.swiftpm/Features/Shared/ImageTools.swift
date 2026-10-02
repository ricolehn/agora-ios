import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Picture preparation before upload: crop and scale on the device, upload JPEG.
enum ImageTools {
    /// Centered crop to [aspect] (width / height), scaled to at most [maxWidth] pixels wide, as JPEG.
    static func jpeg(from data: Data, aspect: CGFloat?, maxWidth: CGFloat, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image, aspect: aspect, maxWidth: maxWidth, quality: quality)
    }

    static func jpeg(from image: UIImage, aspect: CGFloat?, maxWidth: CGFloat, quality: CGFloat = 0.85) -> Data? {
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }
        var crop = CGRect(origin: .zero, size: source)
        if let aspect {
            if source.width / source.height > aspect {
                let width = source.height * aspect
                crop = CGRect(x: (source.width - width) / 2, y: 0, width: width, height: source.height)
            } else {
                let height = source.width / aspect
                crop = CGRect(x: 0, y: (source.height - height) / 2, width: source.width, height: height)
            }
        }
        let scale = min(1, maxWidth / crop.width)
        let target = CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale, width: source.width * scale, height: source.height * scale))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

/// A receipt picked for upload.
struct PickedFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let mimeType: String
    let data: Data
    var preview: UIImage?
}

/// Receipt picker: photos (converted to JPEG) or PDF/image files, up to [limit], each removable.
struct ReceiptPicker: View {
    @Binding var files: [PickedFile]
    var limit = 5
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(files) { file in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let preview = file.preview {
                                        Image(uiImage: preview).resizable().scaledToFill()
                                    } else {
                                        VStack(spacing: 4) {
                                            Image(systemName: "doc.richtext").font(.title2)
                                            Text(file.name).font(.caption2).lineLimit(1)
                                        }
                                        .foregroundStyle(Palette.textSecondary)
                                        .padding(6)
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .background(Palette.surfaceAlt)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button { files.removeAll { $0.id == file.id } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 6, y: -6)
                                .accessibilityLabel("Beleg entfernen")
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            if files.count < limit {
                HStack {
                    PhotosPicker(selection: $photos, maxSelectionCount: limit - files.count, matching: .images) {
                        Label("Fotos", systemImage: "photo.on.rectangle")
                    }
                    Spacer()
                    Button { importing = true } label: { Label("Datei", systemImage: "doc") }
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    guard files.count < limit, let data = try? await item.loadTransferable(type: Data.self),
                          let jpeg = ImageTools.jpeg(from: data, aspect: nil, maxWidth: 2000, quality: 0.8) else { continue }
                    files.append(PickedFile(name: "beleg-\(files.count + 1).jpg", mimeType: "image/jpeg", data: jpeg, preview: UIImage(data: jpeg)))
                }
                photos = []
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls where files.count < limit {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                if data.count > 10 * 1024 * 1024 {
                    toasts.show(String(localized: "Datei zu groß (max. 10 MB)"), error: true)
                    continue
                }
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                if type.conforms(to: .pdf) {
                    files.append(PickedFile(name: url.lastPathComponent, mimeType: "application/pdf", data: data))
                } else if let jpeg = ImageTools.jpeg(from: data, aspect: nil, maxWidth: 2000, quality: 0.8) {
                    files.append(PickedFile(name: url.deletingPathExtension().lastPathComponent + ".jpg", mimeType: "image/jpeg", data: jpeg, preview: UIImage(data: jpeg)))
                }
            }
        }
    }
}

/// Amount text field accepting German input ("12,50").
struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
            Text("€").foregroundStyle(Palette.textSecondary)
        }
    }
}

/// Date picker bound to a "yyyy-MM-dd" text.
struct DayPicker: View {
    let title: LocalizedStringKey
    @Binding var day: String

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Day.date(day) ?? Date() },
            set: { day = Day.string($0) }
        ), displayedComponents: .date)
    }
}

/// Time picker bound to an "HH:mm" text.
struct ClockPicker: View {
    let title: LocalizedStringKey
    @Binding var time: String

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Self.formatter.date(from: time) ?? Self.formatter.date(from: "10:00")! },
            set: { time = Self.formatter.string(from: $0) }
        ), displayedComponents: .hourAndMinute)
    }
}
