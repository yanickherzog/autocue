import ACCore
import Foundation

/// The continuation form's pages (`WA Film II 2007-01`, "zusätzliche
/// Werke") — 4 works each, always the same per-page structure (confirmed
/// directly: identical field positions on all 5 real template pages, only
/// the page's own printed caption/work-numbering differs, which is already
/// baked into the template itself — nothing this computer needs to draw).
/// No checkboxes anywhere on this document — confirmed visually, unlike the
/// main form's two checkbox groups.
extension WAFormLayoutComputer {
    /// Real, measured: work 6's "Werk-Nr." row sits at y=105.133 on every
    /// continuation page (confirmed identical across all 5 real template
    /// pages); the real per-work pitch on this document is 152.2pt — close
    /// to, but genuinely different from, the main form's 150.48 (see
    /// `WAFormWorkBlockGeometry`'s own doc comment).
    private static let continuationFirstWorkBlockTop: Double = 105.133
    private static let continuationWorkBlockPitch: Double = 152.2

    static func continuationPageElements(
        setup: Setup,
        cues: [Cue],
        allCues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> [CueSheetLayoutElement] {
        var elements: [CueSheetLayoutElement] = []

        // "Filmtitel" — real, measured label at y=68.6, x=19.7–56.3; value
        // placed in the real measured blank space below it. **Real,
        // confirmed fix from an actual rendered-output visual check:**
        // y=85 (roughly centered in the box) visually collided with the
        // box's own bottom border line (close to work 6's "Titel" row at
        // y=105.1); y=78 sits cleanly in the upper part of the same blank
        // space instead.
        elements.append(text(setup.title, x: 19.7, y: 78, width: 530))

        for index in 0 ..< worksPerContinuationPage {
            elements.append(contentsOf: workBlockElements(
                cue: index < cues.count ? cues[index] : nil,
                blockTop: continuationFirstWorkBlockTop + Double(index) * continuationWorkBlockPitch,
                geometry: .continuation,
                people: people,
                labels: labels
            ))
        }

        // Round 5 (`docs/DECISIONS.md`, 2026-10-02): confirmed via real text
        // extraction (project owner, cross-checked by Claude against all 5
        // real continuation template pages) that "Name, Vorname oder Firma
        // und Unterschrift aller Rechtsinhaber" — identical real label, real
        // y=712.79, on every one of the 5 real continuation pages, not just
        // the main form's own page 2. This was missing entirely from every
        // continuation page before this round — `otherComposerSignatureLines`
        // was wired only into `mainFormPage2Elements`. Same aggregation,
        // same exclusion (every composer across the whole production except
        // the declarant), drawn again here — the real form's own repeated-
        // per-page signature design, not a dedupe-across-pages situation
        // (a physical page submitted on its own needs its own signatures).
        let signatureLines = otherComposerSignatureLines(
            cues: allCues, excludingDeclarant: setup.declarant, people: people, labels: labels
        )
        if !signatureLines.isEmpty {
            elements.append(text(signatureLines.joined(separator: "\n"), x: 19.7, y: 724, width: 500))
        }

        return elements
    }
}
