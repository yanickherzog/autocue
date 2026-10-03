import ACCore
import Foundation

/// The main WA Film form's two pages (`WA Film 2007-01`) — page 1 (header
/// fields + production-type checkboxes + Works 1–2) and page 2 (Works 3–5 +
/// declarant block + attachment checkboxes). Every coordinate is measured
/// directly from the real template PDF — see `WAFormLayoutComputer`'s own
/// doc comment for the one category (free-text value positions with no
/// printed guide line) that's a reasonable estimate within real measured
/// blank space, not a direct measurement.
extension WAFormLayoutComputer {
    static func mainFormPage1Elements(
        setup: Setup,
        cues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> [CueSheetLayoutElement] {
        var elements = mainFormPage1HeaderElements(setup: setup, people: people, labels: labels)

        elements.append(contentsOf: workBlockElements(
            cue: cues.first,
            blockTop: 496.093,
            geometry: .mainForm,
            people: people,
            labels: labels
        ))
        elements.append(contentsOf: workBlockElements(
            cue: cues.count > 1 ? cues[1] : nil,
            blockTop: 496.093 + workBlockPitch,
            geometry: .mainForm,
            people: people,
            labels: labels
        ))

        return elements
    }

    /// Every page 1 field above the work blocks — split out from
    /// `mainFormPage1Elements` purely to stay under `CONTRIBUTING.md` §8's
    /// `function_body_length` limit; no behavioral boundary beyond that.
    private static func mainFormPage1HeaderElements(
        setup: Setup,
        people: [Person],
        labels: [Label]
    ) -> [CueSheetLayoutElement] {
        var elements: [CueSheetLayoutElement] = []

        // Item 1 (round 3, `docs/DECISIONS.md` 2026-10-02): smaller font,
        // shifted up so the value sits in the real label-to-next-section
        // box's optical vertical center rather than low in it.
        if let isan = setup.isanNumber, !isan.isEmpty {
            elements.append(text(isan, x: 32, y: 96, width: 190, font: smallValueFont))
        }

        // Item 2: title bigger + bold — now two separate elements (not one
        // "\n"-joined string) since `LayoutElementContent.text` carries
        // exactly one font, and the two lines need different ones. Round 4
        // (`docs/DECISIONS.md`, 2026-10-02): the subtitle's font was found,
        // from direct review, smaller than Produzent/Regisseur's — bumped to
        // `emphasizedValueFont` to match (round 3's "unchanged" note for the
        // subtitle is superseded by this correction).
        elements.append(text(setup.title, x: 32, y: 150, width: 530, font: titleFont))
        if let subtitle = setup.subtitle, !subtitle.isEmpty {
            elements.append(text(subtitle, x: 32, y: 168, width: 530, font: emphasizedValueFont))
        }

        // Items 3 & A: bigger font, and now the full resolved address, not
        // just the name — `formattedPartiesWithAddresses` is the one
        // address-formatting helper in this codebase (extracted from this
        // file's own previous declarant-only inline logic; see
        // `+Formatting.swift`), reused here rather than duplicated.
        elements.append(text(
            formattedPartiesWithAddresses(setup.producer, people: people, labels: labels),
            x: 32, y: 205, width: 260, font: emphasizedValueFont
        ))
        elements.append(text(
            formattedPartiesWithAddresses(setup.directorOrPrincipal, people: people, labels: labels),
            x: 303, y: 205, width: 260, font: emphasizedValueFont
        ))

        // Items 4 & 8: three independently-centered digit groups, bigger
        // font — see `durationElements`'s own doc comment.
        elements.append(contentsOf: durationElements(
            setup.productionRuntime,
            centers: DurationFieldCenters(hour: 41.49, minute: 79.17, second: 116.85),
            y: 298, font: emphasizedValueFont
        ))
        elements.append(contentsOf: durationElements(
            setup.totalMusicRuntime,
            centers: DurationFieldCenters(hour: 234.69, minute: 272.37, second: 310.05),
            y: 298, font: emphasizedValueFont
        ))
        // Item 5: bigger font.
        elements.append(text("\(setup.productionYear)", x: 390, y: 299, width: 90, font: emphasizedValueFont))

        // Item 2 (round 4): bigger font, matching Produzent/Regisseur.
        if let broadcasts = setup.knownOrFutureBroadcasts, !broadcasts.isEmpty {
            elements.append(text(broadcasts, x: 32, y: 333, width: 520, font: emphasizedValueFont))
        }

        if let box = additionalWorksCheckboxes[setup.containsAdditionalUndeclaredWorks] {
            elements.append(checkboxMark(at: box))
        }

        for productionType in setup.productionTypes {
            if let box = productionTypeCheckboxes[productionType] {
                elements.append(checkboxMark(at: box))
            }
        }
        if setup.productionTypes.contains(.other), let other = setup.otherProductionTypeDescription, !other.isEmpty {
            elements.append(text(other, x: 439, y: 455, width: 150))
        }

        return elements
    }

    static func mainFormPage2Elements(
        setup: Setup,
        cues: [Cue],
        allCues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> [CueSheetLayoutElement] {
        var elements: [CueSheetLayoutElement] = []

        // Works 3–5: same per-work geometry as works 1–2 (the main form's
        // own `.mainForm` geometry applies on both its pages), starting from
        // page 2's own top margin — the real template has no repeated
        // header on page 2, so work 3's own "Werk-Nr." row sits near y=37.
        let page2BlockTop = 36.972
        for index in 0 ..< worksOnMainPage2 {
            elements.append(contentsOf: workBlockElements(
                cue: index < cues.count ? cues[index] : nil,
                blockTop: page2BlockTop + Double(index) * workBlockPitch,
                geometry: .mainForm,
                people: people,
                labels: labels
            ))
        }

        if let declarant = setup.declarant {
            // Reuses the one address-formatting helper in this codebase
            // (`+Formatting.swift`) — this declarant block is in fact where
            // that pattern originated; extracted in round 3 so items 3 & A's
            // Produzent/Regisseur address rendering can share it too.
            if let declarantText = formattedPartyWithAddress(declarant, people: people, labels: labels) {
                // Real, confirmed fix from an actual rendered-output visual
                // check: the real declarant box's own bottom border sits at
                // y≈637.4 (measured directly from the real template PDF via
                // pdftoppm pixel cropping) — a full 4-line name+address
                // starting at y=592 still crossed it. y=588 gives the full
                // box's real available height room to breathe.
                elements.append(text(declarantText, x: 32, y: 588, width: 370))
            }
        }
        elements.append(text(formattedDate(setup.declarationDate), x: 420, y: 588, width: 150))

        for attachmentType in setup.attachmentTypes {
            if let box = attachmentTypeCheckboxes[attachmentType] {
                elements.append(checkboxMark(at: box))
            }
        }
        if setup.attachmentTypes.contains(.other), let other = setup.otherAttachmentDescription, !other.isEmpty {
            // Real, confirmed fix from an actual rendered-output visual
            // check: placing this beside the "Andere (bitte angeben)" label
            // (its original position) collided with the label's own text —
            // the label's real full width wasn't known at measurement time
            // (only the bare word "Andere" was extracted). Below both
            // checkbox rows, in the real open space before "Einsenden an,"
            // avoids guessing that width.
            elements.append(text(other, x: 32, y: 758, width: 500))
        }

        // Item B (round 3, `docs/DECISIONS.md` 2026-10-02): the "Name,
        // Vorname oder Firma und Unterschrift aller anderen Rechtsinhaber"
        // box — real label at y=643.67, next section ("Beilage (n)") at
        // y=732.23, so the box's own real blank space spans roughly
        // y=654–730. Lists every composer across the whole production
        // (`allCues`, not just this page's 3 works) except the declarant,
        // one per line — `otherComposerSignatureLines` mirrors
        // `CueSheetLayoutComputer+Header.aggregatedPartyIPILines`'s own
        // dedupe-by-`Party`-identity traversal shape, proposed before being
        // implemented per the project owner's explicit request.
        let signatureLines = otherComposerSignatureLines(
            cues: allCues, excludingDeclarant: setup.declarant, people: people, labels: labels
        )
        if !signatureLines.isEmpty {
            elements.append(text(signatureLines.joined(separator: "\n"), x: 32, y: 655, width: 500))
        }

        return elements
    }
}
