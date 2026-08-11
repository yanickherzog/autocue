import ACCore
import ACDesignSystem
import SwiftUI

/// `Setup.productionTypes`'s checkbox grid (SPEC.md §4.2.1) — `ACFeatures`,
/// not `ACDesignSystem`, since it needs `ACCore.ProductionType` directly
/// (`CLAUDE.md`'s Reusable Component Philosophy). A thin wrapper around
/// `CheckboxGridView`, supplying display labels and the "other" conditional
/// description field.
struct ProductionTypePicker: View {
    @Binding var selection: Set<ProductionType>
    @Binding var otherDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CheckboxGridView(items: ProductionType.allCases, label: Self.displayName, selection: $selection)
            if selection.contains(.other) {
                GhostTextField(placeholder: "Please specify", text: $otherDescription)
            }
        }
    }

    /// A lookup table, not a 14-case `switch`, for the same reason
    /// `SetupMapper`'s `ProductionType` raw-value table is one — a `switch`
    /// over all 14 cases trips SwiftLint's `cyclomatic_complexity` threshold
    /// (`CONTRIBUTING.md` §8). `CaseIterable` (already a `ProductionType`
    /// conformance) is what makes `CheckboxGridView`'s `ForEach` safe to drive
    /// from this dictionary — every case is passed to `label` exactly once,
    /// regardless of iteration order.
    static let displayNames: [ProductionType: String] = [
        .featureFilm: "Feature Film",
        .shortFilmCinema: "Short Film (Cinema)",
        .tvFeatureFilm: "TV Feature Film",
        .tvShotFilm: "TV Shot Film",
        .series: "Series",
        .documentaryFilm: "Documentary Film",
        .tvBroadcast: "TV Broadcast",
        .leadInStationID: "Lead-in / Station ID",
        .educationalFilm: "Educational Film",
        .commercial: "Commercial",
        .corporateFilm: "Corporate Film",
        .videoClip: "Video Clip",
        .multimedia: "Multimedia",
        .other: "Other",
    ]

    static func displayName(_ type: ProductionType) -> String {
        // Force-unwrap is safe: `displayNames` is a fixed literal covering
        // every `ProductionType` case, verified by
        // `ProductionTypePickerTests`'s exhaustiveness test, not by
        // `CaseIterable` itself (a dictionary literal isn't compiler-checked
        // for coverage) — same pattern as `SetupMapper.rawValue(for:)`.
        guard let name = displayNames[type] else {
            preconditionFailure("displayNames is missing a case: \(type)")
        }
        return name
    }
}
