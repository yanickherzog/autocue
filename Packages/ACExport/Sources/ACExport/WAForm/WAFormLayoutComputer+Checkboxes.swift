import ACCore
import Foundation

/// Checkbox coordinates and the shared "draw a mark if checked" helper for
/// `WAFormLayoutComputer` — split out per `CONTRIBUTING.md` §8's file-length
/// convention, the same reason `CueSheetLayoutComputer` splits into
/// `+Header`/`+Table`/etc.
///
/// Every coordinate below is the real, measured bounding box of that
/// checkbox's own vector-drawn square on the real template PDF (extracted
/// via `pdftocairo -svg`, cross-referenced against the adjacent label's own
/// `pdftotext -bbox-layout` position to confirm the match) — not estimated.
/// **No box/outline is ever drawn by this app** — the template's own page
/// already prints the empty square; this only draws an "X" mark inside it
/// when checked, reusing `LayoutElementContent.text` (no new case needed).
extension WAFormLayoutComputer {
    /// One checkbox's "X" mark, drawn at `box`'s real, measured square.
    /// **Deliberately not drawn into `box`'s own exact height** — confirmed
    /// real bug, the same class
    /// `PDFCueSheetRendererTests.test_render_everyCueTitle_isActuallyVisibleInTheRenderedText`
    /// already exists to catch for table rows: `CTFrameDraw` silently drops
    /// an entire line of text if its frame is shorter than one line needs,
    /// and the box's own real measured height (~8.87pt) is tighter than an
    /// 8pt bold line actually needs. The height is padded so the glyph
    /// actually renders, re-centered around the checkbox's own real vertical
    /// center so it still visually lands inside the box.
    ///
    /// **Horizontally centered via real glyph measurement, not `box.x`
    /// directly** — a real, confirmed bug from round 3's rendered-output
    /// review (`docs/DECISIONS.md`, 2026-10-02): every checkbox's "X" mark
    /// was consistently off-center in the same direction, because the
    /// previous version used `box.x`/`box.width` as the drawing frame
    /// directly, and Core Text's default (natural/left) paragraph alignment
    /// draws a narrower-than-`width` glyph starting at that left edge rather
    /// than centered within it. Using `WAFormLayoutComputer.centeredText`'s
    /// same real-measurement centering (rather than hand-tuning a per-box
    /// offset) fixes every checkbox at once, uniformly, by removing the root
    /// cause instead of compensating for it.
    ///
    /// **No `checked: Bool` parameter** — every real call site already
    /// decides whether to call this at all (a dictionary lookup against
    /// `setup.productionTypes`/etc.), so a second "is this actually checked"
    /// flag here would just be a second way to express the same fact
    /// (`CLAUDE.md` rule 7).
    ///
    /// **Vertical position is a real, measured constant — not derived from
    /// `box`/`paddedHeight` padding math, which does not actually center a
    /// single `CTFrameDraw`-drawn line vertically** (confirmed empirically,
    /// round 4, `docs/DECISIONS.md` 2026-10-02): an isolated single-checkbox
    /// debug render, pixel-measured, found the drawn "X" glyph's own ink
    /// center sitting measurably above the real box's own center even after
    /// round 3's horizontal-only real-measurement fix — round 3 only ever
    /// addressed horizontal centering, leaving the original, never-verified
    /// `(paddedHeight - box.height) / 2` vertical guess in place. Replaced
    /// here with `checkmarkVerticalOffset`, the real correction that
    /// measurement found, applied uniformly to every checkbox (the project
    /// owner's own explicit requirement — one correction, not per-box
    /// tuning) exactly as round 3's horizontal fix already was.
    private static let checkmarkVerticalOffset: Double = -0.71

    static func checkboxMark(at box: LayoutRect) -> CueSheetLayoutElement {
        let paddedHeight: Double = 12
        let centered = centeredText(
            "X",
            centerX: box.x + box.width / 2,
            y: box.y + checkmarkVerticalOffset,
            font: checkmarkFont
        )
        let frame = LayoutRect(
            x: centered.frame.x,
            y: centered.frame.y,
            width: centered.frame.width,
            height: paddedHeight
        )
        return CueSheetLayoutElement(frame: frame, content: .text("X", font: checkmarkFont))
    }

    // MARK: - Page 1: "Enthält der Film/die Produktion andere musikalische Werke?" (ja/nein/unbekannt)

    static let additionalWorksCheckboxes: [AdditionalWorksDeclaration: LayoutRect] = [
        .yes: LayoutRect(x: 255.97, y: 387.03, width: 8.87, height: 8.87),
        .no: LayoutRect(x: 340.85, y: 387.03, width: 8.87, height: 8.87),
        .notKnown: LayoutRect(x: 425.97, y: 387.03, width: 8.87, height: 8.87),
    ]

    // MARK: - Page 1: the 14-checkbox `ProductionType` grid

    /// Real, measured 4-column grid. Column x-origins: `[29.38, 185.23,
    /// 305.60, 425.97]`; row y-origins: `[425.16, 434.99, 444.58, 454.41]`.
    /// The 4th column only has 2 real checkboxes (Multimedia, Andere) — the
    /// real form's own grid is uneven, not a full 4×4, confirmed directly
    /// from the extracted square count (14, matching `ProductionType`'s 14
    /// cases exactly) rather than assumed.
    static let productionTypeCheckboxes: [ProductionType: LayoutRect] = {
        let columnX: [Double] = [29.38, 185.23, 305.60, 425.97]
        let rowY: [Double] = [425.16, 434.99, 444.58, 454.41]
        let boxSize = 8.7
        // Column-major reading order matches ProductionType's declared case
        // order exactly — confirmed directly against the real grid's visible
        // German labels (Spielfilm Kino → .featureFilm, etc.), not assumed
        // from enum declaration order alone.
        let order: [ProductionType] = [
            .featureFilm, .shortFilmCinema, .tvFeatureFilm, .tvShotFilm,
            .series, .documentaryFilm, .tvBroadcast, .leadInStationID,
            .educationalFilm, .commercial, .corporateFilm, .videoClip,
            .multimedia, .other,
        ]
        let rowsPerColumn = [4, 4, 4, 2]
        var result: [ProductionType: LayoutRect] = [:]
        var cursor = 0
        for (columnIndex, rowCount) in rowsPerColumn.enumerated() {
            for rowIndex in 0 ..< rowCount {
                result[order[cursor]] = LayoutRect(
                    x: columnX[columnIndex],
                    y: rowY[rowIndex],
                    width: boxSize,
                    height: boxSize
                )
                cursor += 1
            }
        }
        return result
    }()

    // MARK: - Page 2: the 4-checkbox `AttachmentType` ("Beilage(n)") grid

    static let attachmentTypeCheckboxes: [AttachmentType: LayoutRect] = [
        .score: LayoutRect(x: 100.11, y: 730.87, width: 8.87, height: 8.87),
        .agreement: LayoutRect(x: 227.68, y: 730.87, width: 8.87, height: 8.87),
        .soundOrVideoCarrier: LayoutRect(x: 100.11, y: 741.66, width: 8.87, height: 8.87),
        .other: LayoutRect(x: 227.68, y: 741.66, width: 8.87, height: 8.87),
    ]
}
