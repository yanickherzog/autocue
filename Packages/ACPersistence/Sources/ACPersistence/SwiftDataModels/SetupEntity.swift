import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.Setup` (SPEC.md §4.2). No `id`
/// — matches the domain type, which has no independent identity outside its
/// owning `Project` (1:1).
///
/// `Party`-typed fields (`producer`/`directorOrPrincipal`/`declarant`) are
/// stored as a flat kind+id pair each, never as a SwiftData `@Relationship`
/// — see `PartyMapper`'s doc comment for why: `DeleteRightHolderUseCase`'s
/// delete guard (ACCore, D3) already assumes bare-UUID references with no
/// cascade/nullify behind them, and a real `@Relationship` here would
/// silently reintroduce exactly that behavior behind the guard's back.
///
/// Each pair is optional (`String?`/`UUID?`), matching `ACCore.Setup`'s
/// `Party?` fields — a brand-new `Project` genuinely has none of these
/// chosen yet (`docs/DECISIONS.md`, "`Setup`'s three `Party` fields become
/// optional").
///
/// `Set<ProductionType>`/`Set<AttachmentType>` are stored as `[String]` raw
/// values (order-independent by construction — reconstructed as a `Set` in
/// `SetupMapper`, so storage order never matters here, unlike the `order`
/// fields on `CueEntity`/`CueRightHolderEntity`/`EmbeddedMarkerEntity`).
@Model
final class SetupEntity {
    var title: String
    var subtitle: String?
    var producerPartyKind: String?
    var producerPartyID: UUID?
    var directorPartyKind: String?
    var directorPartyID: UUID?
    var productionRuntimeSeconds: Double
    var totalMusicRuntimeSeconds: Double
    var productionYear: Int
    var knownOrFutureBroadcasts: String?
    var containsAdditionalUndeclaredWorks: String
    var productionTypesRawValues: [String]
    var otherProductionTypeDescription: String?
    var isanNumber: String?
    var suisaRegistrationNumber: String?
    var seriesTitle: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var productionCountry: String?
    var language: String?
    var timecodeFrameRate: String
    var declarantPartyKind: String?
    var declarantPartyID: UUID?
    var declarationDate: Date
    var attachmentTypesRawValues: [String]
    var otherAttachmentDescription: String?

    init(
        title: String,
        subtitle: String?,
        producerPartyKind: String?,
        producerPartyID: UUID?,
        directorPartyKind: String?,
        directorPartyID: UUID?,
        productionRuntimeSeconds: Double,
        totalMusicRuntimeSeconds: Double,
        productionYear: Int,
        knownOrFutureBroadcasts: String?,
        containsAdditionalUndeclaredWorks: String,
        productionTypesRawValues: [String],
        otherProductionTypeDescription: String?,
        isanNumber: String?,
        suisaRegistrationNumber: String?,
        seriesTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        episodeTitle: String?,
        productionCountry: String?,
        language: String?,
        timecodeFrameRate: String,
        declarantPartyKind: String?,
        declarantPartyID: UUID?,
        declarationDate: Date,
        attachmentTypesRawValues: [String],
        otherAttachmentDescription: String?
    ) {
        self.title = title
        self.subtitle = subtitle
        self.producerPartyKind = producerPartyKind
        self.producerPartyID = producerPartyID
        self.directorPartyKind = directorPartyKind
        self.directorPartyID = directorPartyID
        self.productionRuntimeSeconds = productionRuntimeSeconds
        self.totalMusicRuntimeSeconds = totalMusicRuntimeSeconds
        self.productionYear = productionYear
        self.knownOrFutureBroadcasts = knownOrFutureBroadcasts
        self.containsAdditionalUndeclaredWorks = containsAdditionalUndeclaredWorks
        self.productionTypesRawValues = productionTypesRawValues
        self.otherProductionTypeDescription = otherProductionTypeDescription
        self.isanNumber = isanNumber
        self.suisaRegistrationNumber = suisaRegistrationNumber
        self.seriesTitle = seriesTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.productionCountry = productionCountry
        self.language = language
        self.timecodeFrameRate = timecodeFrameRate
        self.declarantPartyKind = declarantPartyKind
        self.declarantPartyID = declarantPartyID
        self.declarationDate = declarationDate
        self.attachmentTypesRawValues = attachmentTypesRawValues
        self.otherAttachmentDescription = otherAttachmentDescription
    }
}
