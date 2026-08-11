import Foundation
import SwiftData

/// SwiftData-persisted counterpart of `ACCore.Setup` (SPEC.md §4.2). No `id`
/// — matches the domain type, which has no independent identity outside its
/// owning `Project` (1:1).
///
/// `declarant` (`Party?`) is stored as a flat kind+id pair, never as a
/// SwiftData `@Relationship` — see `PartyMapper`'s doc comment for why:
/// `DeleteRightHolderUseCase`'s delete guard (ACCore, D3) already assumes
/// bare-UUID references with no cascade/nullify behind them, and a real
/// `@Relationship` here would silently reintroduce exactly that behavior
/// behind the guard's back. The pair is optional (`String?`/`UUID?`),
/// matching `ACCore.Setup.declarant: Party?` — a brand-new `Project`
/// genuinely has none chosen yet (`docs/DECISIONS.md`, "`Setup`'s three
/// `Party` fields become optional").
///
/// `producer`/`directorOrPrincipal` (`ACCore.Setup`'s `[Party]` fields,
/// `ROADMAP.md` D7 later round) are stored the same bare-reference way, just
/// as two *parallel* arrays each (`producerPartyKinds`/`producerPartyIDs`,
/// same for director) instead of one scalar pair — same reasoning against a
/// real `@Relationship`, extended to a list. See `docs/DECISIONS.md`.
///
/// `Set<ProductionType>`/`Set<AttachmentType>` are stored as `[String]` raw
/// values (order-independent by construction — reconstructed as a `Set` in
/// `SetupMapper`, so storage order never matters here, unlike the `order`
/// fields on `CueEntity`/`CueRightHolderEntity`/`EmbeddedMarkerEntity`).
@Model
final class SetupEntity {
    var title: String
    var subtitle: String?
    var producerPartyKinds: [String]
    var producerPartyIDs: [UUID]
    var directorPartyKinds: [String]
    var directorPartyIDs: [UUID]
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
    var beitrag: String?
    var exploitationTypesRawValues: [String]
    var otherExploitationTypeDescription: String?
    /// A production-level starting reference point for the editor UI's
    /// timecode display (`ACCore.Setup.timecodeStart: Timecode?`) — stored as
    /// a flat, optional offset, the same shape `CueEntity.startTimecodeOffsetSeconds`
    /// already establishes for the same domain type.
    var timecodeStartOffsetSeconds: Double?

    /// `Setup.broadcastDetails: [BroadcastDetails]` ("Sendedatum"/"Sender,
    /// Sendung") — a real to-many relationship, not flat columns on this
    /// entity, since the domain field became a list (`docs/DECISIONS.md`).
    /// Same pattern as `CueEntity.rightHolders`: children are built and
    /// assigned by `SetupMapper`, back-references set only after that
    /// assignment completes.
    @Relationship(deleteRule: .cascade, inverse: \BroadcastDetailsEntity.setup)
    var broadcastDetails: [BroadcastDetailsEntity]

    init(
        title: String,
        subtitle: String?,
        producerPartyKinds: [String],
        producerPartyIDs: [UUID],
        directorPartyKinds: [String],
        directorPartyIDs: [UUID],
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
        otherAttachmentDescription: String?,
        beitrag: String?,
        exploitationTypesRawValues: [String],
        otherExploitationTypeDescription: String?,
        timecodeStartOffsetSeconds: Double?
    ) {
        self.title = title
        self.subtitle = subtitle
        self.producerPartyKinds = producerPartyKinds
        self.producerPartyIDs = producerPartyIDs
        self.directorPartyKinds = directorPartyKinds
        self.directorPartyIDs = directorPartyIDs
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
        self.beitrag = beitrag
        self.exploitationTypesRawValues = exploitationTypesRawValues
        self.otherExploitationTypeDescription = otherExploitationTypeDescription
        self.timecodeStartOffsetSeconds = timecodeStartOffsetSeconds
        broadcastDetails = []
    }
}
