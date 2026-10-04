import ACCore
import CoreGraphics
import CoreText
import Foundation

/// Shared Core Text/Core Graphics drawing primitives for `Canvas`-hosted
/// previews — extracted from `CueSheetPreviewView` (`ROADMAP.md` D11/T11.2)
/// at D12/T12.4, the moment a second real `Canvas`-based preview
/// (`WAFormPreviewView`) needed the identical logic, per `CLAUDE.md` rule 7.
///
/// **Not a style nit — this is the exact class of bug this project has
/// already shipped twice** (`docs/DECISIONS.md`: D11/T11.5's upside-down
/// `CTFrameDraw` text, found only once this code was first composed into
/// real navigation; D12/T12.2's several real `CTFrameDraw` frame-fitting
/// bugs). Sharing one implementation rather than letting a second `Canvas`
/// preview re-derive its own copy of this flip/frame-fit logic removes one
/// entire class of "it diverged from the proven-correct version" risk,
/// mirroring `ACExport`'s own `PDFElementDrawing` extraction (T12.2) for the
/// identical reason, one layer up.
///
/// Mirrors `ACExport`'s `PDFFontMapping.fontName(for:)` exactly — see
/// `CueSheetLayoutComputer`'s own doc comment for why system Helvetica Neue,
/// not this app's Space Grotesk, is this first-pass choice; duplicated here
/// rather than shared since `ACFeatures` cannot depend on `ACExport`
/// (`CLAUDE.md`'s Package Dependency Graph).
enum CanvasElementDrawing {
    /// Draws every element of a precomputed `[CueSheetLayoutElement]` page
    /// into `context` — the identical loop `CueSheetPreviewView.draw(_:in:)`
    /// and `WAFormPreviewView`'s own overlay-drawing step both need.
    /// `context`'s own coordinate space is assumed to already match
    /// `LayoutRect`'s convention for plain rect/line geometry (top-left
    /// origin, y increasing downward) — true for `Canvas`'s own raw
    /// `CGContext` via `GraphicsContext.withCGContext`, per
    /// `CueSheetPreviewView`'s own original finding.
    static func drawElements(_ elements: [CueSheetLayoutElement], in context: CGContext) {
        for element in elements {
            let frame = CGRect(
                x: element.frame.x,
                y: element.frame.y,
                width: element.frame.width,
                height: element.frame.height
            )
            switch element.content {
            case let .text(string, font):
                drawText(string, font: font, in: frame, context: context)
            case let .rule(spec):
                drawRule(spec, in: frame, context: context)
            }
        }
    }

    /// **The real, confirmed fix (`ROADMAP.md` D11/T11.5 manual
    /// verification):** Core Text always lays out and draws a `CTFrame`
    /// assuming a bottom-left-origin, y-*up* coordinate system — the
    /// opposite of `Canvas`'s own raw `CGContext` (top-left-origin, y-down,
    /// to match SwiftUI's view-hosted drawing convention). Left uncorrected,
    /// every glyph draws upside-down. The fix: build the `CTFrame`'s path in
    /// *local* frame-relative coordinates, then flip only around this one
    /// element's own origin before drawing.
    static func drawText(_ string: String, font: LayoutFontSpec, in frame: CGRect, context: CGContext) {
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
        let localPath = CGPath(rect: CGRect(origin: .zero, size: frame.size), transform: nil)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), localPath, nil)

        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.minY + frame.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(ctFrame, context)
        context.restoreGState()
    }

    static func drawRule(_ spec: LayoutRuleSpec, in frame: CGRect, context: CGContext) {
        context.setLineWidth(spec.thickness)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.move(to: CGPoint(x: frame.minX, y: frame.midY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
        context.strokePath()
    }

    static func fontName(for weight: LayoutFontWeight) -> String {
        switch weight {
        case .regular: "HelveticaNeue"
        case .medium: "HelveticaNeue-Medium"
        case .bold: "HelveticaNeue-Bold"
        }
    }
}
