import SwiftUI
import WebKit

/// The community's logo from the server (`/assets/church-logo.svg`, like web and Android). UIImage cannot draw
/// SVG, so it is shown in a small transparent web view; the app mark stands in while loading or without a logo.
struct ServerLogo: View {
    @Environment(AppStore.self) private var store
    var size: CGFloat = 38
    @State private var svg: String?

    var body: some View {
        ZStack {
            if let svg {
                SVGView(svg: svg)
                    .frame(width: size, height: size)
            } else {
                AppMark(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: store.baseURL) {
            guard !store.baseURL.isEmpty else {
                svg = nil
                return
            }
            svg = await LogoCache.shared.svg(store)
        }
    }
}

/// Loaded once per server.
@MainActor
final class LogoCache {
    static let shared = LogoCache()
    private var loaded: [String: String] = [:]
    private var missing: Set<String> = []

    func svg(_ store: AppStore) async -> String? {
        let server = store.baseURL
        if let cached = loaded[server] { return cached }
        if missing.contains(server) { return nil }
        guard let text = try? await store.api.text("/assets/church-logo.svg"), let start = text.range(of: "<svg") else {
            missing.insert(server)
            return nil
        }
        // Only the <svg> element: an XML prolog or comments before it would show up as text in HTML
        let svg = String(text[start.lowerBound...])
        loaded[server] = svg
        return svg
    }
}

/// Renders an SVG document scaled to fit, transparent and without interaction.
struct SVGView: UIViewRepresentable {
    let svg: String

    final class Coordinator {
        var shown: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.shown != svg else { return }
        context.coordinator.shown = svg
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;width:100%;height:100%;background:transparent;overflow:hidden}
        svg{display:block;width:100%;height:100%}</style></head><body>\(svg)</body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
}
