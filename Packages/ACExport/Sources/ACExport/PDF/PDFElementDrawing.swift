import ACCore
import CoreGraphics
import CoreText
import Foundation

/// Draws one `CueSheetLayoutElement`'s content into an already-flipped
/// (bottom-left-origin, Core Graphics-native) `CGRect` — the one real Core
/// Text drawing primitive shared by every PDF renderer in this package
/// (`PDFCueSheetRenderer`, `WAFormRenderer`), extracted so a second renderer
/// needing the same primitive doesn't risk a second, slowly-diverging copy
/// (`CLAUDE.md` rule 7 / this project's own established "extract, don't
/// duplicate across renderers" precedent — see `docs/DECISIONS.md`'s
/// `XLSXCueSheetWriter`/`CueSheetLayoutComputer.columnWidths()` extraction
/// for the same reasoning applied previously).
enum PDFElementDrawing {
    static func drawText(_ string: String, font: LayoutFontSpec, in frame: CGRect, context: CGContext) {
        guard !string.isEmpty else { return }
        let ctFont = CTFontCreateWithName(PDFFontMapping.fontName(for: font.weight) as CFString, font.size, nil)
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

    static func drawRule(_ spec: LayoutRuleSpec, in frame: CGRect, context: CGContext) {
        context.setLineWidth(spec.thickness)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.move(to: CGPoint(x: frame.minX, y: frame.midY))
        context.addLine(to: CGPoint(x: frame.maxX, y: frame.midY))
        context.strokePath()
    }
}
