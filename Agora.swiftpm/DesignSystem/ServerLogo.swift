import CryptoKit
import SwiftUI
import WebKit

/// The community's logo from the server (`/assets/church-logo.svg`, like web and Android). The last known logo shows at
/// once (kept on the device, `LogoStore`), then the server is checked and a changed logo swaps in; the app mark stands
/// in while there is none or the server shows its default logo.
struct ServerLogo: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    var size: CGFloat = 38

    var body: some View {
        let logos = LogoStore.shared
        let kept = logos.logo(store.baseURL)
        let appearance: LogoStore.Appearance = colorScheme == .dark ? .dark : .light
        ZStack {
            if let svg = kept.svg {
                if let picture = kept.pictures[appearance] {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFit()
                } else {
                    // Until it is drawn as a picture (once per logo and appearance)
                    SVGView(svg: svg)
                }
            } else {
                AppMark(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: store.baseURL) { await logos.refresh(store.api) }
        // Back in the foreground: a logo changed meanwhile comes in (the store asks at most once a minute)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await logos.refresh(store.api) } }
        }
        .task(id: "\(store.baseURL)|\(appearance.rawValue)|\(logos.revision)") { await logos.draw(store.baseURL, appearance) }
    }
}

/// The church logo of each server, kept on the device (like Android's LogoStore): the app opens with the last known
/// logo (no flash of the bundled knot), then asks the server and takes a new one, or goes back to the bundled knot when
/// the server shows its default logo again. Logos are public, so they stay on logout; offline the kept one stays. The
/// SVG is drawn into a picture once per appearance, so the header needs no web view.
@MainActor
@Observable
final class LogoStore {
    static let shared = LogoStore()

    enum Appearance: String, CaseIterable { case light, dark }

    struct Kept {
        /// nil: the bundled Agora knot.
        var svg: String?
        var pictures: [Appearance: UIImage] = [:]
    }

    /// Bumped when a kept logo changed, so the views showing it redraw.
    private(set) var revision = 0
    @ObservationIgnored private var kept: [String: Kept] = [:]
    @ObservationIgnored private var checkedAt: [String: Date] = [:]
    @ObservationIgnored private var checking: Set<String> = []
    /// Pictures being drawn, or that could not be drawn (no retry for the same logo).
    @ObservationIgnored private var drawn: Set<String> = []
    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("server-logo", isDirectory: true) ?? FileManager.default.temporaryDirectory.appendingPathComponent("server-logo")
        self.directory = base
    }

    /// The logo kept for [baseURL] (read from the device the first time, so the screen opening now already shows it).
    func logo(_ baseURL: String) -> Kept {
        _ = revision
        guard !baseURL.isEmpty else { return Kept() }
        if let known = kept[baseURL] { return known }
        var loaded = Kept(svg: try? String(contentsOf: file(baseURL, "svg"), encoding: .utf8))
        if loaded.svg != nil {
            for appearance in Appearance.allCases {
                if let data = try? Data(contentsOf: file(baseURL, "\(appearance.rawValue).png")), let image = UIImage(data: data) {
                    loaded.pictures[appearance] = image
                }
            }
        }
        kept[baseURL] = loaded
        return loaded
    }

    /// Asks the server for its logo (at most once a minute per server). A changed logo is kept, the default logo removes
    /// the kept one; without an answer (offline, server down) everything stays as it is.
    func refresh(_ api: APIClient) async {
        let base = api.baseURL
        guard !base.isEmpty, !checking.contains(base) else { return }
        if let last = checkedAt[base], Date().timeIntervalSince(last) < 60 { return }
        checking.insert(base)
        defer { checking.remove(base) }
        guard let text = try? await api.text("/assets/church-logo.svg"), let svg = ServerLogoRules.svgElement(text) else { return }
        checkedAt[base] = Date()
        let current = logo(base)
        if ServerLogoRules.isDefaultLogo(svg) {
            guard current.svg != nil else { return }
            removeFiles(base)
            update(base, Kept())
        } else if svg != current.svg {
            removeFiles(base)
            write(Data(svg.utf8), to: file(base, "svg"))
            update(base, Kept(svg: svg))
        }
    }

    /// Draws the kept logo of [baseURL] for [appearance] once, when there is no picture yet.
    func draw(_ baseURL: String, _ appearance: Appearance) async {
        let current = logo(baseURL)
        guard let svg = current.svg, current.pictures[appearance] == nil else { return }
        let key = "\(baseURL)|\(appearance.rawValue)|\(svg.hashValue)"
        guard !drawn.contains(key) else { return }
        drawn.insert(key)
        guard let image = await SVGSnapshot().render(svg, size: 96, style: appearance == .dark ? .dark : .light),
              SVGSnapshot.hasContent(image), logo(baseURL).svg == svg else { return }
        var updated = logo(baseURL)
        updated.pictures[appearance] = image
        if let png = image.pngData() { write(png, to: file(baseURL, "\(appearance.rawValue).png")) }
        update(baseURL, updated)
    }

    private func update(_ baseURL: String, _ value: Kept) {
        kept[baseURL] = value
        revision += 1
    }

    // MARK: Files (Application Support, not in backups)

    private func file(_ baseURL: String, _ suffix: String) -> URL {
        let digest = SHA256.hash(data: Data(baseURL.droppingSuffix("/").utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest.prefix(24)).\(suffix)")
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        try? data.write(to: url, options: .atomic)
    }

    private func removeFiles(_ baseURL: String) {
        for suffix in ["svg"] + Appearance.allCases.map({ "\($0.rawValue).png" }) {
            try? FileManager.default.removeItem(at: file(baseURL, suffix))
        }
    }
}

/// A web view for logos: transparent, no interaction and no JavaScript (an uploaded SVG is shown, never run).
private func logoWebView(frame: CGRect) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: frame, configuration: configuration)
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.isScrollEnabled = false
    view.isUserInteractionEnabled = false
    return view
}

private func logoPage(_ svg: String) -> String {
    """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>html,body{margin:0;padding:0;width:100%;height:100%;background:transparent;overflow:hidden}
    svg{display:block;width:100%;height:100%}</style></head><body>\(svg)</body></html>
    """
}

/// Renders an SVG document scaled to fit, transparent and without interaction.
struct SVGView: UIViewRepresentable {
    let svg: String

    final class Coordinator {
        var shown: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView { logoWebView(frame: .zero) }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.shown != svg else { return }
        context.coordinator.shown = svg
        view.loadHTMLString(logoPage(svg), baseURL: nil)
    }
}

/// Draws an SVG in an offscreen web view and takes a picture of it (header logo, financial report).
@MainActor
final class SVGSnapshot: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    /// [style]: the appearance the SVG's own light / dark styles follow.
    func render(_ svg: String, size: CGFloat, style: UIUserInterfaceStyle = .light) async -> UIImage? {
        let view = logoWebView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.overrideUserInterfaceStyle = style
        view.navigationDelegate = self
        // A web view outside a window often snapshots blank: add it invisibly while it draws
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        view.alpha = 0.01
        window?.addSubview(view)
        defer { view.removeFromSuperview() }
        let loaded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.continuation = continuation
            view.loadHTMLString(logoPage(svg), baseURL: nil)
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

    /// Whether a snapshot shows anything: a web view that did not draw gives a fully transparent picture.
    static func hasContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 8 }
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
