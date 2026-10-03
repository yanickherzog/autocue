import ACCore
import CoreGraphics
import CoreText
import Foundation

/// Computes `[CueSheetPageLayout]` for the literal SUISA WA Film
/// registration form's **overlay** content only (`ROADMAP.md` D12, SPEC.md
/// §2.1) — `Setup`/`Cue` values and checkbox marks, positioned at real
/// coordinates measured directly from the user's own real form PDFs
/// (`WA Film 2007-01 D.doc` main form, `WA Film II 2007-01 F.doc`
/// continuation), never the form's own printed labels/boxes/lines — those
/// come from `template`'s own pages, drawn as a background by
/// `WAFormRenderer`. This is the entire reason this computer only ever
/// produces `.text` elements, never `.rule`: every line/box this document
/// needs is already printed on the page it overlays.
///
/// **Coordinates below were extracted directly from the real, user-supplied
/// reference PDFs — `pdftotext -bbox-layout` for every text-anchored field,
/// and the real vector-drawn checkbox squares' own path coordinates
/// (`pdftocairo -svg`) for every checkbox — not estimated from a screenshot.
/// A handful of free-text value positions (the production title, producer/
/// director addresses) have no printed guide line on the real form to
/// anchor against, so they're placed within the real, measured blank space
/// between labels — flagged here as the one category of position in this
/// file that's a reasonable estimate, not a direct measurement, and the
/// first thing to check against a real rendered PDF.** Expect a real
/// visual-polish pass once this renders for the first time, the same way
/// `CueSheetLayoutComputer` (D11/T11.2) needed nine-plus rounds — this is a
/// first, real pass grounded in real measurement, not a finished design.
///
/// **Fixed-position, fixed-capacity layout — a different shape from
/// `CueSheetLayoutComputer`'s dynamic, pack-to-capacity one.** Every work's
/// position on every page is a known constant — confirmed real per-work
/// vertical pitch, independently measured per document (150.48pt on the main
/// form, 152.2pt on the continuation form — close but genuinely different,
/// not assumed shared; see `WAFormWorkBlockGeometry`) — so there is no
/// text-measurement-driven pagination question the way the cue sheet has
/// one. Pagination here is pure arithmetic: the main form always holds
/// exactly 5 works (2 on page 1, 3 on page 2 — confirmed real split, not an
/// even 2.5), the continuation form always holds exactly 4 works per page.
enum WAFormLayoutComputer {
    // MARK: - Page geometry (points, matching the real template's own A4 portrait size exactly)

    static let pageWidth: Double = 595.7
    static let pageHeight: Double = 841.227

    static let valueFont = LayoutFontSpec(weight: .regular, size: 9)
    static let checkmarkFont = LayoutFontSpec(weight: .bold, size: 8)

    /// Real-rendered-output visual-review fixes (round 3, 2026-10-02,
    /// `docs/DECISIONS.md`): several specific fields were found too small
    /// relative to the real template's own printed labels, or needed real
    /// typographic emphasis to read as a heading rather than a value. Named
    /// per-field rather than a single "bigger" constant because the sizes
    /// genuinely differ (a page title is not the same weight/size question
    /// as a right-holder's percentage share) — see each call site for which
    /// one applies.
    static let smallValueFont = LayoutFontSpec(weight: .regular, size: 8)
    static let emphasizedValueFont = LayoutFontSpec(weight: .regular, size: 10)
    static let titleFont = LayoutFontSpec(weight: .bold, size: 13)
    static let workTitleFont = LayoutFontSpec(weight: .bold, size: 10)

    /// Works 1–2 live on the main form's page 1; works 3–5 on page 2 — the
    /// real, confirmed, uneven split (`docs/DECISIONS.md`, 2026-09-27 T11.3
    /// revalidation), not an even 2.5. Four works per continuation page
    /// thereafter, confirmed against all five real continuation-template
    /// pages (6–9, 10–13, 14–17, 18–21, 22–25).
    static let worksOnMainPage1 = 2
    static let worksOnMainPage2 = 3
    static let worksPerContinuationPage = 4

    /// Entry point. `continuationPagesAvailable` is however many pages the
    /// user's own imported continuation-form PDF actually has (read live by
    /// `ExportRepositoryImpl`, never hardcoded) — cues beyond what the main
    /// form plus that many continuation pages can hold are simply not drawn
    /// here. **Deliberately silent about that overflow** — surfacing it as a
    /// validation issue is `ROADMAP.md` T12.3's job, not this pure layout
    /// function's; this function's only contract is "never draw more than
    /// the template can actually hold."
    static func computeLayout(for project: Project, continuationPagesAvailable: Int) -> [CueSheetPageLayout] {
        let setup = project.setup
        let people = project.people
        let labels = project.labels
        let cues = project.cues

        var pages: [[CueSheetLayoutElement]] = []

        let page1Cues = Array(cues.prefix(worksOnMainPage1))
        pages.append(mainFormPage1Elements(setup: setup, cues: page1Cues, people: people, labels: labels))

        let page2Cues = cues.count > worksOnMainPage1
            ? Array(cues[worksOnMainPage1 ..< min(worksOnMainPage1 + worksOnMainPage2, cues.count)])
            : []
        pages.append(mainFormPage2Elements(
            setup: setup,
            cues: page2Cues,
            allCues: cues,
            people: people,
            labels: labels
        ))

        var remaining = cues.count > (worksOnMainPage1 + worksOnMainPage2)
            ? Array(cues[(worksOnMainPage1 + worksOnMainPage2)...])
            : []
        var continuationPagesUsed = 0
        while !remaining.isEmpty, continuationPagesUsed < continuationPagesAvailable {
            let pageCues = Array(remaining.prefix(worksPerContinuationPage))
            pages.append(continuationPageElements(
                setup: setup, cues: pageCues, allCues: cues, people: people, labels: labels
            ))
            remaining.removeFirst(pageCues.count)
            continuationPagesUsed += 1
        }

        let pageCount = pages.count
        return pages.enumerated().map { index, elements in
            CueSheetPageLayout(pageIndex: index, pageCount: pageCount, elements: elements)
        }
    }

    /// The main form's own real, confirmed per-work vertical pitch —
    /// confirmed distinct from the continuation form's own pitch (152.2,
    /// `+ContinuationForm.swift`), not assumed shared. `blockTop` is the
    /// y-coordinate of that work's "Werk-Nr."/"Dauer" label row.
    static let workBlockPitch: Double = 150.48

    /// **Height is sized to the string's real line count and real
    /// per-line font measurement, never a flat constant** — confirmed real
    /// bug, the same class `checkboxMark(at:)` already documents:
    /// `CTFrameDraw` silently drops whichever lines don't fit the given
    /// frame. Two real, confirmed rounds of this exact failure mode: a flat
    /// `height: 14` (round 2) silently dropped a title's subtitle line and a
    /// resolved party's entire address; a flat `height: 12` (round 2's own
    /// fix, still a constant) was in turn too short once round 3 introduced
    /// bigger fonts (`titleFont`/`workTitleFont`, 13pt/10pt bold) — a bold
    /// 13pt title line silently vanished the same way. Round 3's real fix
    /// (`docs/DECISIONS.md`, 2026-10-02) reuses
    /// `CueSheetLayoutComputer.lineHeight(fontSize:weight:)` — the real Core
    /// Text ascent/descent/leading measurement already built for exactly
    /// this purpose — instead of inventing a second, parallel height
    /// constant that would only need its own future correction the next
    /// time a call site's font size changes.
    ///
    /// The declarant block's real measured box constraint (bottom border at
    /// y≈637.4, `pdftoppm` pixel-cropped — not text-anchored, so not
    /// Core-Text-measurable) still applies independently of this — see
    /// `+MainForm.swift`'s declarant call site.
    ///
    /// **A third real, confirmed finding on top of the above, from the same
    /// round 3 rendered-output check:** `lineHeight`'s own bare
    /// ascent+descent+leading sum is *itself* occasionally too tight for
    /// `CTFrameDraw` to actually fit a line in — isolated directly (a 9pt
    /// regular single line, frame height exactly equal to the measured
    /// value, silently dropped; +0.5pt was enough to fix it, in that one
    /// isolated case). `CueSheetLayoutComputer`'s own call sites never hit
    /// this because every one of them already adds real padding on top of
    /// `lineHeight` for its own layout reasons (e.g. `cellVerticalPadding`);
    /// this file's call sites didn't, having adopted the bare measurement
    /// directly. `frameFitMargin` is a deliberate, generous fixed safety
    /// margin (not the bare minimum found above) added once, here, so every
    /// caller gets it rather than each needing to remember its own padding.
    private static let frameFitMargin: Double = 2

    static func text(
        _ string: String,
        x: Double,
        y: Double,
        width: Double,
        font: LayoutFontSpec = valueFont
    ) -> CueSheetLayoutElement {
        let lineCount = string.components(separatedBy: "\n").count
        let perLineHeight = CueSheetLayoutComputer.lineHeight(fontSize: font.size, weight: font.weight) + frameFitMargin
        return CueSheetLayoutElement(
            frame: LayoutRect(x: x, y: y, width: width, height: Double(lineCount) * perLineHeight),
            content: .text(string, font: font)
        )
    }

    /// A single-line string, horizontally centered on `centerX` using its
    /// **real, measured** glyph width (Core Text, the exact same measurement
    /// `PDFElementDrawing` draws with — not an assumed/estimated width).
    ///
    /// Added for round 3's real-rendered-output review (`docs/DECISIONS.md`,
    /// 2026-10-02): the per-field hh/mm/ss duration groups (items 4 & 8) must
    /// each land centered over their own printed blank, and `checkboxMark`'s
    /// own "X" mark was found consistently off-center for the same root
    /// cause this fixes — `text()`'s frame starts at a fixed `x`, so a
    /// narrower-than-`width` glyph always renders left-biased, not centered,
    /// under Core Text's default (natural/left) paragraph alignment. Real
    /// measurement removes the guesswork entirely instead of hand-tuning a
    /// per-field offset.
    static func centeredText(
        _ string: String,
        centerX: Double,
        y: Double,
        font: LayoutFontSpec
    ) -> CueSheetLayoutElement {
        let ctFont = CTFontCreateWithName(PDFFontMapping.fontName(for: font.weight) as CFString, font.size, nil)
        let attributedString = NSAttributedString(
            string: string,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont]
        )
        let line = CTLineCreateWithAttributedString(attributedString)
        let measuredWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let measuredHeight = CueSheetLayoutComputer
            .lineHeight(fontSize: font.size, weight: font.weight) + frameFitMargin
        return CueSheetLayoutElement(
            frame: LayoutRect(x: centerX - measuredWidth / 2, y: y, width: measuredWidth, height: measuredHeight),
            content: .text(string, font: font)
        )
    }
}
