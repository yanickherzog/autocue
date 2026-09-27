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
    /// One "Label: Value" pair in the header block's two-column grid —
    /// Name der Sendung / Genre / Regie / Produktion / Komponist-IPI /
    /// Verwertung / Jahr / Sendedatum, per the real cue sheet example this
    /// Task is built from.
    struct HeaderLine: Equatable {
        let label: String
        let value: String
    }

    static func headerBlockLines(for project: Project) -> [HeaderLine] {
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

        return [
            HeaderLine(label: "Name der Sendung", value: emptyDash(name)),
            HeaderLine(label: "Genre", value: emptyDash(genre)),
            HeaderLine(label: "Regie", value: emptyDash(regie)),
            HeaderLine(label: "Produktion", value: emptyDash(produktion)),
            HeaderLine(label: "Komponist-IPI", value: emptyDash(ipi)),
            HeaderLine(label: "Verwertung", value: emptyDash(verwertung)),
            HeaderLine(label: "Jahr", value: String(setup.productionYear)),
            HeaderLine(label: "Sendedatum", value: emptyDash(sendedatum)),
        ]
    }

    static func headerBlockHeight(lines: [HeaderLine], columnWidth: Double) -> Double {
        headerBlockRows(lines: lines).reduce(0) { total, row in
            total + headerRowHeight(row: row, columnWidth: columnWidth)
        }
    }

    static func headerBlockElements(lines: [HeaderLine], usableWidth: Double) -> [CueSheetLayoutElement] {
        let columnWidth = usableWidth / 2
        var elements: [CueSheetLayoutElement] = []
        var originY = margin
        for row in headerBlockRows(lines: lines) {
            let rowHeight = headerRowHeight(row: row, columnWidth: columnWidth)
            elements.append(headerCellElement(
                row.left,
                originX: margin,
                originY: originY,
                width: columnWidth,
                height: rowHeight
            ))
            elements.append(headerCellElement(
                row.right,
                originX: margin + columnWidth,
                originY: originY,
                width: columnWidth,
                height: rowHeight
            ))
            originY += rowHeight
        }
        return elements
    }

    /// One line per unique composer across every `Cue` on the project, each
    /// `"Name: IPI Nr. <number>"` — confirmed against the real cue sheet
    /// example (2026-09-27), which showed multiple composers stacked
    /// vertically in this header cell, each with their own name *and* IPI
    /// number, not the number alone. **A real, self-caught bug, fixed here:
    /// an earlier version returned only the bare IPI numbers, with no name
    /// attached — unusable on a real document, since nobody reading it could
    /// tell whose number is whose.** Deduplicated by the composer's `Party`
    /// identity (not by IPI number), so the same person listed as composer
    /// on more than one `Cue` appears once, not once per `Cue`. A composer
    /// with no IPI number on file shows their bare name — never omitted,
    /// never a blank/placeholder number in its place.
    static func composerIPILines(cues: [Cue], people: [Person], labels: [Label]) -> [String] {
        var seenComposers = Set<Party>()
        var lines: [String] = []
        for cue in cues {
            for rightHolder in cue.rightHolders where rightHolder.role == .composer {
                guard !seenComposers.contains(rightHolder.party),
                      let resolved = PartyResolver.resolve(rightHolder.party, people: people, labels: labels)
                else { continue }
                seenComposers.insert(rightHolder.party)
                if let ipiNumber = resolved.ipiNumber, !ipiNumber.isEmpty {
                    lines.append("\(resolved.displayName): IPI Nr. \(ipiNumber)")
                } else {
                    lines.append(resolved.displayName)
                }
            }
        }
        return lines
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

    private static func headerBlockRows(lines: [HeaderLine]) -> [(left: HeaderLine, right: HeaderLine)] {
        var rows: [(left: HeaderLine, right: HeaderLine)] = []
        var index = 0
        while index + 1 < lines.count {
            rows.append((left: lines[index], right: lines[index + 1]))
            index += 2
        }
        return rows
    }

    private static func headerRowHeight(row: (left: HeaderLine, right: HeaderLine), columnWidth: Double) -> Double {
        let innerWidth = columnWidth - cellHorizontalPadding * 2
        let leftHeight = measuredHeight(
            text: headerCellText(row.left),
            width: innerWidth,
            fontSize: headerFontSize,
            weight: .regular
        )
        let rightHeight = measuredHeight(
            text: headerCellText(row.right),
            width: innerWidth,
            fontSize: headerFontSize,
            weight: .regular
        )
        return max(leftHeight, rightHeight) + cellVerticalPadding * 2
    }

    private static func headerCellText(_ line: HeaderLine) -> String {
        "\(line.label): \(line.value)"
    }

    private static func headerCellElement(
        _ line: HeaderLine,
        originX: Double,
        originY: Double,
        width: Double,
        height: Double
    ) -> CueSheetLayoutElement {
        CueSheetLayoutElement(
            frame: LayoutRect(
                x: originX + cellHorizontalPadding,
                y: originY + cellVerticalPadding,
                width: width - cellHorizontalPadding * 2,
                height: height - cellVerticalPadding * 2
            ),
            content: .text(headerCellText(line), font: LayoutFontSpec(weight: .regular, size: headerFontSize))
        )
    }
}
