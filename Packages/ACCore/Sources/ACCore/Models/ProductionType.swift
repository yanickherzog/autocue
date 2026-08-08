import Foundation

/// The SUISA form's production-type checkbox grid (SPEC.md §4.2.1).
///
/// Modeled as a `Set<ProductionType>` on `Setup`, not a single value, because
/// the form presents independent checkboxes — a production can legitimately
/// be both `.series` and `.tvBroadcast`.
public enum ProductionType: Equatable, Hashable, CaseIterable, Sendable {
    case featureFilm
    case shortFilmCinema
    case tvFeatureFilm
    case tvShotFilm
    case series
    case documentaryFilm
    case tvBroadcast
    case leadInStationID
    case educationalFilm
    case commercial
    case corporateFilm
    case videoClip
    case multimedia
    case other
}
