import SwiftUI

// iPad / regular width (like the web from 769px): the page uses the whole width with a margin that grows with
// the screen, and content goes into columns. iPhone (compact width) stays as it is.

private struct PageContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 350
}

private struct PageGutterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 20
}

private struct PageScrollKey: EnvironmentKey {
    static let defaultValue: ScrollViewProxy? = nil
}

extension EnvironmentValues {
    /// Scrolls the current tab page to a view with an `.id` (e.g. a day in the Termine list); set by TabPage.
    var pageScroll: ScrollViewProxy? {
        get { self[PageScrollKey.self] }
        set { self[PageScrollKey.self] = newValue }
    }

    /// Width of a tab page's content (between the page margins); set by TabPage.
    var pageContentWidth: CGFloat {
        get { self[PageContentWidthKey.self] }
        set { self[PageContentWidthKey.self] = newValue }
    }

    /// Side margin of the current tab page; set by TabPage.
    var pageGutter: CGFloat {
        get { self[PageGutterKey.self] }
        set { self[PageGutterKey.self] = newValue }
    }
}

enum PageLayout {
    /// 20pt on iPhone, growing with the screen on iPad (web: clamp(20px, 2.8vw, 64px)).
    static func gutter(width: CGFloat, regular: Bool) -> CGFloat {
        regular ? min(max(width * 0.028, 24), 56) : 20
    }
}

/// Cards as a grid of columns at least [minWidth] wide on iPad, one below the other on iPhone.
struct AdaptiveGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var minWidth: CGFloat
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if sizeClass == .regular && minWidth.isFinite {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: spacing, alignment: .top)], alignment: .leading, spacing: spacing) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}

/// Two columns next to each other on iPad (from 840pt content width), otherwise one below the other.
struct TwoPane<Left: View, Right: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.pageContentWidth) private var width
    var spacing: CGFloat = 16
    var leftShare: CGFloat = 0.53
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        if sizeClass == .regular && width >= 760 {
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) { left }
                    .frame(width: (width - spacing) * leftShare)
                VStack(alignment: .leading, spacing: spacing) { right }
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                left
                right
            }
        }
    }
}
