import SwiftUI
import UIKit

/// Loads pictures through the API client (profile pictures need the token), memory-cached; the HTTP cache of the
/// client keeps them on disk as long as the server allows.
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private var missing: Set<URL> = []
    private var running: [URL: Task<UIImage?, Never>] = [:]
    var api: APIClient?

    private init() { memory.countLimit = 300 }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func isMissing(_ url: URL) -> Bool { missing.contains(url) }

    func image(_ url: URL) async -> UIImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        if missing.contains(url) { return nil }
        if let task = running[url] { return await task.value }
        let api = api
        let task = Task<UIImage?, Never> {
            guard let api else { return nil }
            let request = api.request(url)
            guard let data = try? await api.execute(request, reportUnauthorized: false) else { return nil }
            return await Task.detached(priority: .userInitiated) { UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) }.value
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) } else { missing.insert(url) }
        return image
    }

    /// After uploading a new picture: forget the old one.
    func forget(_ url: URL) {
        memory.removeObject(forKey: url as NSURL)
        missing.remove(url)
    }

    func clear() {
        memory.removeAllObjects()
        missing.removeAll()
    }
}

/// Picture from the server with a placeholder while loading or when there is none.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// Bumped to reload after a new upload.
    var revision = 0
    @ViewBuilder var placeholder: Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: "\(url?.absoluteString ?? "")#\(revision)") {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImagePipeline.shared.cached(url) {
                image = cached
                return
            }
            image = nil
            let loaded = await ImagePipeline.shared.image(url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// 16:9 event picture: a 16:9 frame sets the size (full width), the picture fills exactly that frame. The picture
/// itself never decides the size, so it is not zoomed in further on wide or narrow screens.
struct CoverImage<Placeholder: View, Overlay: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: Placeholder
    @ViewBuilder var overlay: Overlay

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    if let url {
                        RemoteImage(url: url) { placeholder }
                    } else {
                        placeholder
                    }
                    overlay
                }
            }
            .clipped()
    }
}

extension CoverImage where Overlay == EmptyView {
    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
        self.overlay = EmptyView()
    }
}

/// Round avatar: picture of the account, else initials; optional role ring like the web app.
struct Avatar: View {
    @Environment(AppStore.self) private var store
    let userId: String?
    let name: String
    var size: CGFloat = 40
    var ring: AvatarRingKind?
    /// Anonymous partner (mentoring): a shield instead of initials, never a picture.
    var anonymous = false
    var revision = 0

    var body: some View {
        let inner = ZStack {
            Circle().fill(LinearGradient(colors: [Palette.violet.opacity(0.16), Palette.primary.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if anonymous {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Palette.primary)
            } else {
                RemoteImage(url: userId.flatMap { store.repository.profilePictureURL($0) }, revision: revision) {
                    Text(Initials.of(name))
                        .font(.system(size: size * 0.36, weight: .heavy))
                        .foregroundStyle(Palette.text)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())

        Group {
            if let ring {
                inner
                    .padding(2)
                    .background(Circle().fill(Palette.surface))
                    .padding(3)
                    .background(Circle().fill(ring.gradient))
                    .shadow(color: ring.glow, radius: 5, y: 2)
            } else {
                inner
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(anonymous ? "Anonym" : name))
    }
}

extension AvatarRingKind {
    var gradient: LinearGradient {
        switch self {
        case .standard: return LinearGradient(colors: [Color(hex: 0x06B6D4), Color(hex: 0x10B981)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mentor: return LinearGradient(colors: [Color(hex: 0xC084FC), Color(hex: 0x7C3AED)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .manager: return LinearGradient(colors: [Color(hex: 0xFACC15), Color(hex: 0xEF4444)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var glow: Color {
        switch self {
        case .standard: return Color(hex: 0x06B6D4, opacity: 0.35)
        case .mentor: return Color(hex: 0x7C3AED, opacity: 0.42)
        case .manager: return Color(hex: 0xEF4444, opacity: 0.38)
        }
    }
}

/// Server logo (`/assets/church-logo.svg` is SVG, which UIImage cannot draw): the app's own mark instead.
struct AppMark: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Palette.brand)
            Image(systemName: "building.columns.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: 0x06B6D4, opacity: 0.3), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Toasts

/// Short feedback after an action ("Gespeichert"), shown at the top with a colored accent bar.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private(set) var current: Toast?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ text: String, error: Bool = false) {
        hideTask?.cancel()
        withAnimation(.spring(duration: 0.35)) { current = Toast(text: text, isError: error) }
        UIAccessibility.post(notification: .announcement, argument: text)
        let haptics = UINotificationFeedbackGenerator()
        haptics.notificationOccurred(error ? .error : .success)
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { current = nil }
        }
    }

    func error(_ error: Error) { show(APIError.text(error), error: true) }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { current = nil }
    }
}

struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Palette.danger : Palette.success)
                    Text(toast.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(topLeadingRadius: Radius.control, bottomLeadingRadius: Radius.control, style: .continuous)
                        .fill(toast.isError ? Palette.danger : Palette.success)
                        .frame(width: 5)
                }
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 15, y: 6)
                .padding(.horizontal, 16)
                .frame(maxWidth: 520)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { toasts.dismiss() }
                .id(toast.id)
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(toasts.current != nil)
    }
}

/// Runs one async action at a time with feedback: success text as toast, errors as red toast.
@MainActor
@Observable
final class ActionRunner {
    private(set) var busy = false

    func run(_ toasts: ToastCenter, success: String? = nil, _ work: @escaping () async throws -> Void, done: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await work()
                if let success { toasts.show(success) }
                done?()
            } catch is CancellationError {
            } catch {
                toasts.error(error)
            }
        }
    }
}
