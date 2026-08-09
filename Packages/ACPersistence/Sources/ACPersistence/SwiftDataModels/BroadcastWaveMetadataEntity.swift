import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.BroadcastWaveMetadata`
/// (SPEC.md §4.10). Kept as its own entity — related to `AudioAssetEntity`
/// as a to-one optional — rather than flattened directly onto
/// `AudioAssetEntity`'s columns: every field here is independently optional,
/// so an all-`nil` flattened state would be ambiguous with "this file has no
/// `bext` chunk at all," unlike `PostalAddress`'s genuinely all-or-nothing
/// shape (see `PersonEntity`'s doc comment).
///
/// Property named `descriptionText`, not `description` — avoids shadowing
/// `CustomStringConvertible.description` were this type ever to conform.
@Model
final class BroadcastWaveMetadataEntity {
    var descriptionText: String?
    var originator: String?
    var originatorReference: String?
    var originationDate: Date?
    var timeReferenceSamples: UInt64?

    init(
        descriptionText: String?,
        originator: String?,
        originatorReference: String?,
        originationDate: Date?,
        timeReferenceSamples: UInt64?
    ) {
        self.descriptionText = descriptionText
        self.originator = originator
        self.originatorReference = originatorReference
        self.originationDate = originationDate
        self.timeReferenceSamples = timeReferenceSamples
    }
}
