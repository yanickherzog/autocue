import ACCore
import Foundation

/// One "musical work" block's overlay content — shared by the main form's
/// two pages and every continuation page. Both documents use the same
/// *structure* (confirmed: the duration-field offset, the right-holder
/// section's offset, and its 3-row pitch are all within 0.1pt of each other
/// across both real files), but **not the same absolute x-coordinates** —
/// confirmed by direct measurement, not assumed: the continuation form's
/// left margin sits ~8.6pt further left than the main form's (`Titel`
/// starts at x=19.7 on the continuation form vs. x=28.3 on the main form).
/// `WorkBlockGeometry` holds one document's own real, independently-measured
/// values; `.mainForm`/`.continuation` below are the two real instances.
struct WAFormWorkBlockGeometry {
    let titleX: Double
    let durationHourCenterX: Double
    let durationMinuteCenterX: Double
    let durationSecondCenterX: Double
    let durationOffsetY: Double
    let firstRightHolderRowOffsetY: Double
    let rightHolderNameX: Double
    let rightHolderNameWidth: Double
    let broadcastShareX: Double
    let mechanicalShareX: Double
    let shareColumnWidth: Double

    /// Real, measured from the main WA Film form (`WA Film 2007-01`, work 1:
    /// `Werk-Nr.` at y=496.093, right-holder dotted rows at
    /// y=572.7/592.1/611.5, name dotted line x=91.4–385.7, broadcast-share
    /// dotted line x=401.0–475.7, mechanical-share dotted line x=488.9–563.5).
    /// The three duration center-x values are each individual `"___"`
    /// blank's own real measured center (`pdftotext -bbox-layout`, work 1's
    /// duration line at y=513.28: `___` x=471.36–490.50, `___`
    /// x=509.19–528.18, `___` x=546.87–565.86) — round 3's fix (item 4 & 8,
    /// `docs/DECISIONS.md` 2026-10-02) replaces the single combined
    /// `durationX` this struct used to carry with these three, since each
    /// digit group is now drawn and centered independently rather than as
    /// one "hh:mm:ss" string.
    static let mainForm = WAFormWorkBlockGeometry(
        titleX: 28.3,
        durationHourCenterX: 480.93,
        durationMinuteCenterX: 518.69,
        durationSecondCenterX: 556.36,
        durationOffsetY: 17.2,
        firstRightHolderRowOffsetY: 76.6,
        rightHolderNameX: 91.4,
        rightHolderNameWidth: 294.3,
        broadcastShareX: 401.0,
        mechanicalShareX: 488.9,
        shareColumnWidth: 74.6
    )

    /// Real, measured from the continuation form (`WA Film II 2007-01`,
    /// work 6: `Werk-Nr.` at y=105.133, right-holder dotted rows at
    /// y=181.7/201.1/220.6, name dotted line x=82.8–377.0, broadcast-share
    /// dotted line x=392.2–466.8, mechanical-share dotted line
    /// x=480.0–554.6). Duration center-x values measured the same way as
    /// `.mainForm`, from work 6's own duration line at y=122.32: `___`
    /// x=470.40–489.54, `___` x=508.23–527.22, `___` x=545.91–564.90 — close
    /// to, but genuinely different from, the main form's own (confirmed by
    /// direct measurement, not assumed shared, matching this struct's own
    /// established precedent for every other field).
    static let continuation = WAFormWorkBlockGeometry(
        titleX: 19.7,
        durationHourCenterX: 479.97,
        durationMinuteCenterX: 517.73,
        durationSecondCenterX: 555.41,
        durationOffsetY: 17.2,
        firstRightHolderRowOffsetY: 76.6,
        rightHolderNameX: 82.8,
        rightHolderNameWidth: 294.2,
        broadcastShareX: 392.2,
        mechanicalShareX: 480.0,
        shareColumnWidth: 74.6
    )
}

extension WAFormLayoutComputer {
    /// **Three rows only — a real, confirmed capacity limit of the physical
    /// form, not a display choice.** Confirmed by direct measurement on both
    /// real documents (19.4pt row pitch, 3 dotted lines, no more). A `Cue`
    /// with more than 3 non-`.performer` right-holders has nowhere on this
    /// physical form to go beyond these three rows — flagged for
    /// `ROADMAP.md` T12.3's own validation pass, not solved here; this
    /// function silently draws only the first 3.
    private static let rightHolderRowCount = 3
    private static let rightHolderRowPitch: Double = 19.4

    static func workBlockElements(
        cue: Cue?,
        blockTop: Double,
        geometry: WAFormWorkBlockGeometry,
        people: [Person],
        labels: [Label]
    ) -> [CueSheetLayoutElement] {
        guard let cue else { return [] }

        var elements: [CueSheetLayoutElement] = []

        // Item 7 (round 3, `docs/DECISIONS.md` 2026-10-02): bigger + bold,
        // consistent across every work title on both documents.
        elements.append(text(cue.title, x: geometry.titleX, y: blockTop + 12, width: 220, font: workTitleFont))

        // Item 11: `Werk-Nr.` is no longer rendered at all, anywhere — the
        // project owner confirmed this field should be removed entirely,
        // not repositioned or restyled. `Cue.workNumber` itself is untouched
        // (a domain field, `CLAUDE.md` rule 9); this is a display-only
        // removal from the overlay.

        // Items 4 & 8: three independently-centered digit groups over the
        // template's own three printed blanks, never a combined "hh:mm:ss"
        // string — see `durationElements`'s own doc comment for why.
        //
        // Round 4 (`docs/DECISIONS.md`, 2026-10-02): `geometry.durationOffsetY`
        // is the real, measured blank-line position itself — drawing
        // directly at it sat the digits ON the printed line (confirmed via
        // a real rendered-output crop), not above it the way the
        // right-holder rows/percentages already correctly sit. Round 4's own
        // `-7` nudge sat too high (round 5, confirmed via a side-by-side
        // rendered comparison of several candidate offsets against the real
        // template) — `-6` is the smallest adjustment that still leaves a
        // clean, visible gap above the printed blank.
        elements.append(contentsOf: durationElements(
            cue.duration,
            centers: DurationFieldCenters(
                hour: geometry.durationHourCenterX,
                minute: geometry.durationMinuteCenterX,
                second: geometry.durationSecondCenterX
            ),
            y: blockTop + geometry.durationOffsetY - 6,
            font: emphasizedValueFont
        ))

        let rightHolders = cue.rightHolders.filter { $0.role != .performer }.prefix(rightHolderRowCount)
        for (rowIndex, rightHolder) in rightHolders.enumerated() {
            let rowY = blockTop + geometry.firstRightHolderRowOffsetY + Double(rowIndex) * rightHolderRowPitch
            // Items 9 & 10: bigger font, shifted upward so the text sits
            // on/above its dotted line rather than centered below it — `rowY`
            // is the dotted line's own real measured y; the previous version
            // used it directly as the drawing frame's top, which put the
            // glyph's visible ink below the line instead of resting on it.
            let rightHolderTextY = rowY - 7
            elements.append(text(
                rightHolderLine(rightHolder, people: people, labels: labels),
                x: geometry.rightHolderNameX,
                y: rightHolderTextY,
                width: geometry.rightHolderNameWidth,
                font: emphasizedValueFont
            ))
            elements.append(text(
                formattedPercent(rightHolder.performanceBroadcastShare),
                x: geometry.broadcastShareX,
                y: rightHolderTextY,
                width: geometry.shareColumnWidth,
                font: emphasizedValueFont
            ))
            elements.append(text(
                formattedPercent(rightHolder.mechanicalRightsShare),
                x: geometry.mechanicalShareX,
                y: rightHolderTextY,
                width: geometry.shareColumnWidth,
                font: emphasizedValueFont
            ))
        }

        return elements
    }
}
