import ACCore
import ACDesignSystem
import CoreGraphics
import CoreText
import SwiftUI

/// Draws the identical, precomputed `[CueSheetPageLayout]`
/// `PDFCueSheetRenderer` (`ACExport`) also draws — `ROADMAP.md` D11/T11.2,
/// built in the same Task as the layout computation and the PDF renderer so
/// preview and export are verified against each other directly from day one
/// (per the project owner's own explicit reasoning for pulling this into
/// T11.2 rather than deferring to T11.5).
///
/// **Deliberately drops down to a raw `CGContext` via
/// `GraphicsContext.withCGContext`, and draws text via the same
/// `CTFramesetter`/`CTFrameDraw` calls `PDFCueSheetRenderer` uses — never
/// SwiftUI's native `Text` view inside this `Canvas`.** This is the actual
/// mechanism behind `CLAUDE.md`'s "the preview View deliberately does not
/// use SwiftUI's native `Text`/`VStack` layout for the form content": using
/// `Text` here would route through SwiftUI's own text engine, which can
/// disagree with Core Text's line-breaking/wrapping — exactly the silent
/// preview/export divergence this whole architecture exists to prevent.
/// `ACFeatures` cannot depend on `ACExport` (`CLAUDE.md`'s Package
/// Dependency Graph), so this draw logic is necessarily a separate copy
/// from `PDFCueSheetRenderer`'s — but it calls the identical Core Text APIs
/// against a `CGContext`, so the two can't visually diverge regardless of
/// being two source files, the same guarantee as the font-name mapping this
/// screen's own `fontName(for:)` duplicates from `ACExport`'s
/// `PDFFontMapping`.
public struct CueSheetPreviewView: View {
    @Bindable var viewModel: CueSheetPreviewViewModel

    public init(viewModel: CueSheetPreviewViewModel) {
        _viewModel = Bindable(viewModel)
    }

    /// A4 landscape, matching `CueSheetLayoutComputer`'s own page geometry
    /// exactly — duplicated here rather than shared for the same
    /// cross-package reason as the font mapping above.
    private static let pageWidth: CGFloat = 841.89
    private static let pageHeight: CGFloat = 595.28

    public var body: some View {
        Group {
            if viewModel.projectNotFound {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Project Not Found",
                    message: "This project may have been deleted.",
                    surface: .reversed
                )
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { _, page in
                            pageView(page)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.reversed.background)
        .task {
            await viewModel.load()
        }
    }

    private func pageView(_ page: CueSheetPageLayout) -> some View {
        Canvas { context, _ in
            draw(page, in: context)
        }
        .frame(width: Self.pageWidth, height: Self.pageHeight)
        .background(Color.white)
    }

    private func draw(_ page: CueSheetPageLayout, in context: GraphicsContext) {
        context.withCGContext { cgContext in
            // `Canvas`'s own coordinate space already matches `LayoutRect`'s
            // convention (top-left origin, y increasing downward) — unlike
            // `PDFCueSheetRenderer`'s Core Graphics `PDFContext`, no flip is
            // needed here.
            for element in page.elements {
                let frame = CGRect(
                    x: element.frame.x,
                    y: element.frame.y,
                    width: element.frame.width,
                    height: element.frame.height
                )
                switch element.content {
                case let .text(string, font):
                    drawText(string, font: font, in: frame, context: cgContext)
                case let .rule(spec):
                    drawRule(spec, in: frame, context: cgContext)
                }
            }
        }
    }

    private func drawText(_ string: String, font: LayoutFontSpec, in frame: CGRect, context: CGContext) {
        guard !string.isEmpty else { return }
        let ctFont = CTFontCreateWithName(fontName(for: font.weight) as CFString, font.size, nil)
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: ctFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1),
        ]
        if font.tracking != 0 {
            attributes[kCTKernAttributeName as NSAttributedString.Key] = font.tracking
        }
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: frame, transform: nil)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(ctFrame, context)
    }

    private func drawRule(_ spec: LayoutRuleSpec, in frame: CGRect, context: CGContext) {
        context.setLineWidth(spec.thickness)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.move(to: CGPoint(x: frame.minX, y: frame.midY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
        context.strokePath()
    }

    /// Matches `ACExport`'s `PDFFontMapping.fontName(for:)` exactly — see
    /// `CueSheetLayoutComputer`'s own doc comment for why system Helvetica
    /// Neue, not this app's Space Grotesk, is this Task's deliberate,
    /// easily-revisited first-pass choice.
    private func fontName(for weight: LayoutFontWeight) -> String {
        switch weight {
        case .regular: "HelveticaNeue"
        case .medium: "HelveticaNeue-Medium"
        case .bold: "HelveticaNeue-Bold"
        }
    }
}
