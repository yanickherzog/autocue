import ACCore
import Foundation

/// Display-string formatting for `CueSheetLayoutComputer` (SPEC.md §4.16) —
/// split out per `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length`
/// limit; see `+Header.swift`'s doc comment for the full rationale.
///
/// `displayName(_:)` and `formattedLength(_:)` duplicate mappings that
/// already exist in `ACFeatures` (`SetupView`'s production-/exploitation-
/// type pickers; `CueDetectionReviewViewModel+TableRows.swift`'s `MM:SS`
/// formatter) — `ACExport` cannot depend on `ACFeatures` (`CLAUDE.md`'s
/// Package Dependency Graph), so a small, deliberate duplication here is the
/// correct tradeoff, not an oversight.
extension CueSheetLayoutComputer {
    static func partyNames(_ parties: [Party], people: [Person], labels: [Label]) -> String {
        parties.compactMap { PartyResolver.resolve($0, people: people, labels: labels)?.displayName }
            .joined(separator: ", ")
    }

    /// A dictionary lookup, not a 14-case `switch` — `CONTRIBUTING.md` §8's
    /// `SwiftLint` `cyclomatic_complexity` limit flagged the `switch` form
    /// (each case counted as a branch); a fixed lookup table has none.
    private static let productionTypeDisplayNames: [ProductionType: String] = [
        .featureFilm: "Spielfilm",
        .shortFilmCinema: "Kurzfilm (Kino)",
        .tvFeatureFilm: "TV-Spielfilm",
        .tvShotFilm: "TV-Kurzfilm",
        .series: "Serie",
        .documentaryFilm: "Dokumentarfilm",
        .tvBroadcast: "TV-Sendung",
        .leadInStationID: "Vorspann/Senderkennung",
        .educationalFilm: "Lehrfilm",
        .commercial: "Werbespot",
        .corporateFilm: "Firmenfilm",
        .videoClip: "Videoclip",
        .multimedia: "Multimedia",
        .other: "Sonstige",
    ]

    static func displayName(_ productionType: ProductionType) -> String {
        productionTypeDisplayNames[productionType] ?? "Sonstige"
    }

    static func displayName(_ exploitationType: ExploitationType) -> String {
        switch exploitationType {
        case .cinema: "Kino"
        case .tv: "TV"
        case .festival: "Festival"
        case .other: "Sonstige"
        }
    }

    /// `MM:SS` — duplicates `CueDetectionReviewViewModel+TableRows.swift`'s
    /// own deliberate exception to `MediaDuration.formatted`'s general
    /// `HH:MM:SS`: a single cue's usage duration realistically never runs
    /// past an hour, unlike `Setup.totalMusicRuntime` (SPEC.md §4.3).
    static func formattedLength(_ duration: MediaDuration) -> String {
        let totalSeconds = Int(duration.seconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
