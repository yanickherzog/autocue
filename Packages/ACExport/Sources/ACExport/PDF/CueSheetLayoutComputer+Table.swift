import ACCore
import Foundation

/// Table (column-header row, cue rows, footer) computation for
/// `CueSheetLayoutComputer` (SPEC.md §4.16) — split out per
/// `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length` limit; see
/// `+Header.swift`'s doc comment for the full rationale.
extension CueSheetLayoutComputer {
    static func columnHeaderElements(widths: [Double], top: Double, height: Double) -> [CueSheetLayoutElement] {
        var elements: [CueSheetLayoutElement] = []
        var originX = margin
        for (column, width) in zip(columns, widths) {
            elements.append(CueSheetLayoutElement(
                frame: LayoutRect(
                    x: originX + cellHorizontalPadding,
                    y: top + cellVerticalPadding,
                    width: width - cellHorizontalPadding * 2,
                    height: height - cellVerticalPadding * 2
                ),
                content: .text(column.title, font: LayoutFontSpec(weight: .bold, size: columnHeaderFontSize))
            ))
            originX += width
        }
        elements.append(ruleElement(top: top + height, width: widths.reduce(0, +)))
        return elements
    }

    /// One value per column, in `columns`' order — Komponist*in /
    /// Arrangeur*in / Interpret*in / Songtitel / TC In / TC Out / Dur. /
    /// Label / Label-Nr. / ISRC-Nr. **Performer right-holders resolve into
    /// Interpret*in, not excluded** — confirmed against the real cue
    /// sheet example (SPEC.md §4.16, `docs/DECISIONS.md`, 2026-09-27),
    /// unlike D12's WA-form exclusion. No percentage shares render here at
    /// all — names only.
    static func rowValues(for cue: Cue, setup: Setup, people: [Person], labels: [Label]) -> [String] {
        let (tcIn, tcOut) = tcInOut(for: cue, setup: setup)
        return [
            names(for: .composer, cue: cue, people: people, labels: labels),
            names(for: .arranger, cue: cue, people: people, labels: labels),
            names(for: .performer, cue: cue, people: people, labels: labels),
            cue.title,
            tcIn,
            tcOut,
            formattedLength(cue.duration),
            cue.recordingLabel ?? "",
            cue.recordingLabelNumber ?? "",
            cue.recordingISRC ?? "",
        ]
    }

    static func rowElements(cells: [String], widths: [Double], top: Double, height: Double) -> [CueSheetLayoutElement] {
        var elements: [CueSheetLayoutElement] = []
        var originX = margin
        for (cell, width) in zip(cells, widths) {
            elements.append(CueSheetLayoutElement(
                frame: LayoutRect(
                    x: originX + cellHorizontalPadding,
                    y: top + cellVerticalPadding,
                    width: width - cellHorizontalPadding * 2,
                    height: height - cellVerticalPadding * 2
                ),
                content: .text(cell, font: LayoutFontSpec(weight: .regular, size: cellFontSize))
            ))
            originX += width
        }
        elements.append(ruleElement(top: top + height, width: widths.reduce(0, +)))
        return elements
    }

    /// Right-aligned to the **Dur. column's own right edge specifically**
    /// (index 6 of `columns`) — not loosely centered across Dur.+Label, a
    /// real, self-caught fix from the project owner's second visual pass
    /// (2026-09-28, `docs/DECISIONS.md`): the prior version's right edge was
    /// the *end of Label*, and also clamped the drawn frame's width down to
    /// the Dur.+Label span even when the text's own natural width was
    /// wider — since `CTFrameDraw` wraps text that doesn't fit its frame,
    /// that clamp could have silently wrapped "TOTAL MUSIK: HH:MM:SS" onto
    /// a second line the moment that span got narrow enough. Always using
    /// the text's real natural (unwrapped) width for the frame, and letting
    /// it extend *leftward* from Dur.'s right edge into the blank space
    /// below the table, avoids both problems at once. Positioned directly
    /// at `originY` — immediately below the last table row (plus
    /// `tableToFooterGap`), not pinned to the page's bottom margin the way
    /// this element used to be. Right-alignment is computed here, as a
    /// frame position, rather than via a `LayoutElementContent` alignment
    /// case — every existing `.text` call site/pattern match would need
    /// updating for a case that only this one element ever uses
    /// (`CueSheetLayoutComputer+Measurement.swift`'s `measuredWidth` doc
    /// comment has the full reasoning).
    static func footerElement(
        project: Project,
        columnWidths: [Double],
        originY: Double,
        height: Double
    ) -> CueSheetLayoutElement {
        let text = totalMusikText(for: project)
        let durColumnEnd = margin + columnWidths[0 ..< 7].reduce(0, +)
        let textWidth = measuredWidth(text: text, fontSize: footerFontSize, weight: .bold)
        return CueSheetLayoutElement(
            frame: LayoutRect(x: durColumnEnd - textWidth, y: originY, width: textWidth, height: height),
            content: .text(text, font: LayoutFontSpec(weight: .bold, size: footerFontSize))
        )
    }

    /// The "TOTAL MUSIK: HH:MM:SS" text, shared verbatim with the XLSX
    /// writer (`XLSXCueSheetWriter`, `ROADMAP.md` D11/T11.4) — pulled out of
    /// `footerElement` so the two renderers can never silently drift apart
    /// on this string, rather than each hand-writing the same interpolation.
    /// The XLSX writer uses this as a row *label* only — its own "TOTAL
    /// MUSIK" cell is a live `=SUM()` formula over real numeric Dur. cells,
    /// not this precomputed text, per the project owner's explicit decision
    /// that this one value should be a genuinely usable spreadsheet total,
    /// not a static copy of the PDF's rendered string.
    static func totalMusikText(for project: Project) -> String {
        "TOTAL MUSIK: \(project.setup.totalMusicRuntime.formatted)"
    }

    private static func names(for role: CueRightHolderRole, cue: Cue, people: [Person], labels: [Label]) -> String {
        cue.rightHolders
            .filter { $0.role == role }
            .compactMap { PartyResolver.resolve($0.party, people: people, labels: labels)?.displayName }
            .joined(separator: ", ")
    }

    /// SPEC.md §4.3: TC In = `Setup.timecodeStart + Cue.startTimecode`;
    /// TC Out = TC In + `Cue.duration`. A `nil` `startTimecode` (a manually
    /// entered or not-yet-positioned cue) has no on-screen position to
    /// derive from — renders as "—" for both, rather than a misleading zero.
    private static func tcInOut(for cue: Cue, setup: Setup) -> (in: String, out: String) {
        guard let startTimecode = cue.startTimecode, let timecodeStart = setup.timecodeStart else {
            return ("—", "—")
        }
        let tcIn = Timecode(offsetSeconds: timecodeStart.offsetSeconds + startTimecode.offsetSeconds)
        let tcOut = Timecode(offsetSeconds: tcIn.offsetSeconds + cue.duration.seconds)
        return (tcIn.formatted(at: setup.timecodeFrameRate), tcOut.formatted(at: setup.timecodeFrameRate))
    }

    private static func ruleElement(top: Double, width: Double) -> CueSheetLayoutElement {
        CueSheetLayoutElement(
            frame: LayoutRect(x: margin, y: top, width: width, height: ruleThickness),
            content: .rule(LayoutRuleSpec(thickness: ruleThickness))
        )
    }
}
