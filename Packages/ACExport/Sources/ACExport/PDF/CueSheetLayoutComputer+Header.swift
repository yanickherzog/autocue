import ACCore
import Foundation

/// Header-block computation for `CueSheetLayoutComputer` (SPEC.md §4.16) —
/// split into its own file per `CONTRIBUTING.md` §8's `SwiftLint`
/// `type_body_length` limit, the same reason `SetupView`/
/// `CueDetectionReviewViewModel` are already split this way. Members here
/// are `internal` (no `private`), since Swift's `private` is file-scoped —
/// `CueSheetLayoutComputer.swift`'s `computeLayout` calls straight into this
/// file's top-level functions.
extension CueSheetLayoutComputer {
    /// One "Label: Value" field in the header block's two-column grid —
    /// each rendered as a bold label element immediately followed by a
    /// regular-weight value element on the same line (`headerFieldElements`,
    /// below), per the real cue sheet mockup this layout-redesign pass is
    /// built from.
    struct HeaderLine: Equatable {
        let label: String
        let value: String
    }

    /// **Left column: Name der Sendung / Regie / Produktion / Komponist*in.
    /// Right column: Genre / Jahr / Verwertung / Sendedatum.** Returned as
    /// two independent arrays, zipped by index into rows (`headerBlockElements`,
    /// below) — not one flat 8-element array paired by adjacent index, which
    /// is how this used to work before the redesign and produced a
    /// different, now-superseded pairing (`docs/DECISIONS.md`).
    static func headerBlockLines(for project: Project) -> (left: [HeaderLine], right: [HeaderLine]) {
        let setup = project.setup
        let people = project.people
        let labels = project.labels

        let name = [setup.title, setup.subtitle].compactMap { $0 }.joined(separator: " — ")
        let genre = setup.productionTypes.map(displayName).sorted().joined(separator: ", ")
        let regie = partyNames(setup.directorOrPrincipal, people: people, labels: labels)
        let produktion = partyNames(setup.producer, people: people, labels: labels)
        let ipi = composerIPILines(cues: project.cues, people: people, labels: labels).joined(separator: "\n")
        let verwertung = setup.exploitationTypes.map(displayName).sorted().joined(separator: ", ")
        let sendedatum = broadcastDetailsLine(setup.broadcastDetails)

        let left = [
            HeaderLine(label: "Name der Sendung", value: emptyDash(name)),
            HeaderLine(label: "Regie", value: emptyDash(regie)),
            HeaderLine(label: "Produktion", value: emptyDash(produktion)),
            HeaderLine(label: "Komponist*in", value: emptyDash(ipi)),
        ]
        let right = [
            HeaderLine(label: "Genre", value: emptyDash(genre)),
            HeaderLine(label: "Jahr", value: String(setup.productionYear)),
            HeaderLine(label: "Verwertung", value: emptyDash(verwertung)),
            HeaderLine(label: "Sendedatum", value: emptyDash(sendedatum)),
        ]
        return (left, right)
    }

    static func headerBlockHeight(left: [HeaderLine], right: [HeaderLine], columnWidth: Double) -> Double {
        zip(left, right).reduce(0) { total, pair in
            total + headerRowHeight(left: pair.0, right: pair.1, columnWidth: columnWidth)
        }
    }

    static func headerBlockElements(
        left: [HeaderLine],
        right: [HeaderLine],
        top: Double,
        usableWidth: Double
    ) -> [CueSheetLayoutElement] {
        let columnWidth = usableWidth / 2
        var elements: [CueSheetLayoutElement] = []
        var originY = top
        for (leftLine, rightLine) in zip(left, right) {
            let rowHeight = headerRowHeight(left: leftLine, right: rightLine, columnWidth: columnWidth)
            elements.append(contentsOf: headerFieldElements(
                leftLine,
                originX: margin,
                originY: originY,
                width: columnWidth,
                height: rowHeight
            ))
            elements.append(contentsOf: headerFieldElements(
                rightLine,
                originX: margin + columnWidth,
                originY: originY,
                width: columnWidth,
                height: rowHeight
            ))
            originY += rowHeight
        }
        return elements
    }

    /// One line per unique right-holder of `role` across every `Cue` on the
    /// project, each `"Name, IPI-Nr. <grouped number>"` — the shared
    /// aggregation behind both the Komponist*in header field
    /// (`composerIPILines`, below) and the Interpret*innen summary block
    /// (`performerIPILines`, `+InterpretBlock.swift`), now nearly identical
    /// in shape (layout-redesign pass) so pulled into one generic helper
    /// rather than duplicated per role. Deduplicated by the right-holder's
    /// `Party` identity (not by IPI number), so the same person listed on
    /// more than one `Cue` appears once, not once per `Cue`. A right-holder
    /// with no IPI number on file shows their bare name — never omitted,
    /// never a blank/placeholder number in its place.
    static func aggregatedPartyIPILines(
        cues: [Cue],
        role: CueRightHolderRole,
        people: [Person],
        labels: [Label]
    ) -> [String] {
        var seen = Set<Party>()
        var lines: [String] = []
        for cue in cues {
            for rightHolder in cue.rightHolders where rightHolder.role == role {
                guard !seen.contains(rightHolder.party),
                      let resolved = PartyResolver.resolve(rightHolder.party, people: people, labels: labels)
                else { continue }
                seen.insert(rightHolder.party)
                lines.append(formattedNameWithIPI(resolved))
            }
        }
        return lines
    }

    static func composerIPILines(cues: [Cue], people: [Person], labels: [Label]) -> [String] {
        aggregatedPartyIPILines(cues: cues, role: .composer, people: people, labels: labels)
    }

    static func performerIPILines(cues: [Cue], people: [Person], labels: [Label]) -> [String] {
        aggregatedPartyIPILines(cues: cues, role: .performer, people: people, labels: labels)
    }

    private static func formattedNameWithIPI(_ resolved: ResolvedParty) -> String {
        guard let ipiNumber = resolved.ipiNumber, !ipiNumber.isEmpty else {
            return resolved.displayName
        }
        return "\(resolved.displayName), IPI-Nr. \(formattedIPI(ipiNumber))"
    }

    /// Groups the trailing 9 digits of a stored IPI number as `3-2-2-2`
    /// (`"123 45 67 89"`) — confirmed against the real cue sheet mockup
    /// (`docs/DECISIONS.md`, layout-redesign pass): `ProjectFixture`'s
    /// composer stores `"00123456789"` (11 digits — the standard 2-digit
    /// zero-padding prefix + 9-digit base number), and the mockup renders
    /// exactly `"123 45 67 89"` — the leading padding dropped, the
    /// remaining 9 digits grouped 3-2-2-2. Degrades gracefully for a
    /// shorter/malformed number (fewer/shorter trailing groups) rather than
    /// crashing — this field is free text (`SPEC.md` §4.5/§4.12), never
    /// validated against a fixed format on entry.
    static func formattedIPI(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.count > 9 {
            digits = String(digits.suffix(9))
        }
        guard !digits.isEmpty else { return raw }

        var groups: [String] = []
        var remaining = Substring(digits)
        let firstCount = min(3, remaining.count)
        groups.append(String(remaining.prefix(firstCount)))
        remaining = remaining.dropFirst(firstCount)
        while !remaining.isEmpty {
            let count = min(2, remaining.count)
            groups.append(String(remaining.prefix(count)))
            remaining = remaining.dropFirst(count)
        }
        return groups.joined(separator: " ")
    }

    static func broadcastDetailsLine(_ details: [BroadcastDetails]) -> String {
        details
            .map { detail in
                [detail.broadcaster, detail.programmeName, detail.date.map { dateFormatter.string(from: $0) }]
                    .compactMap { $0 }
                    .joined(separator: " – ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    private static func emptyDash(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }

    private static func headerRowHeight(left: HeaderLine, right: HeaderLine, columnWidth: Double) -> Double {
        max(headerFieldHeight(left, columnWidth: columnWidth), headerFieldHeight(right, columnWidth: columnWidth))
    }

    /// A field's own required height: its bold `"Label:"` is always exactly
    /// one line; its value (possibly multi-line — the Komponist*in field
    /// stacks one line per composer, `composerIPILines` above) wraps within
    /// whatever width remains after the label, not the full column.
    private static func headerFieldHeight(_ line: HeaderLine, columnWidth: Double) -> Double {
        let innerWidth = columnWidth - cellHorizontalPadding * 2
        let labelWidth = measuredWidth(text: headerLabelText(line), fontSize: headerFontSize, weight: .bold)
        let labelHeight = lineHeight(fontSize: headerFontSize, weight: .bold)
        let valueWidth = max(innerWidth - labelWidth - headerLabelValueGap, 1)
        let valueHeight = measuredHeight(
            text: line.value,
            width: valueWidth,
            fontSize: headerFontSize,
            weight: .regular
        )
        return max(labelHeight, valueHeight) + headerFieldVerticalPadding * 2
    }

    private static func headerLabelText(_ line: HeaderLine) -> String {
        "\(line.label):"
    }

    /// Two elements, not one — a bold label immediately followed by a
    /// regular-weight value on the same line, since `LayoutElementContent
    /// .text` carries a single `LayoutFontSpec` for its whole string
    /// (`CueSheetLayoutComputer`'s own doc comment on `headerLabelValueGap`).
    private static func headerFieldElements(
        _ line: HeaderLine,
        originX: Double,
        originY: Double,
        width: Double,
        height: Double
    ) -> [CueSheetLayoutElement] {
        let innerX = originX + cellHorizontalPadding
        let innerWidth = width - cellHorizontalPadding * 2
        let innerY = originY + headerFieldVerticalPadding
        let innerHeight = height - headerFieldVerticalPadding * 2

        let labelText = headerLabelText(line)
        let labelWidth = measuredWidth(text: labelText, fontSize: headerFontSize, weight: .bold)
        let labelHeight = lineHeight(fontSize: headerFontSize, weight: .bold)
        let labelElement = CueSheetLayoutElement(
            frame: LayoutRect(x: innerX, y: innerY, width: labelWidth, height: labelHeight),
            content: .text(labelText, font: LayoutFontSpec(weight: .bold, size: headerFontSize))
        )

        let valueX = innerX + labelWidth + headerLabelValueGap
        let valueWidth = max(innerWidth - labelWidth - headerLabelValueGap, 1)
        let valueElement = CueSheetLayoutElement(
            frame: LayoutRect(x: valueX, y: innerY, width: valueWidth, height: innerHeight),
            content: .text(line.value, font: LayoutFontSpec(weight: .regular, size: headerFontSize))
        )

        return [labelElement, valueElement]
    }
}
