import Foundation

/// One per `Project` — the production-level header, mirroring the SUISA WA
/// Film form's top section almost 1:1 (SPEC.md §4.2).
///
/// No `id` field: `Setup` has no independent identity of its own outside the
/// `Project` it belongs to (1:1), the same "no `id` field, no `Identifiable`"
/// shape as `PostalAddress`/`Party` (`CLAUDE.md`, "Domain Model Value-Type
/// Conformances").
public struct Setup: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let producer: Party
    public let directorOrPrincipal: Party
    public let productionRuntime: MediaDuration
    public let totalMusicRuntime: MediaDuration
    public let productionYear: Int
    public let knownOrFutureBroadcasts: String?
    public let containsAdditionalUndeclaredWorks: AdditionalWorksDeclaration
    public let productionTypes: Set<ProductionType>
    public let otherProductionTypeDescription: String?
    public let isanNumber: String?
    public let suisaRegistrationNumber: String?
    public let seriesTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeTitle: String?
    public let productionCountry: String?
    public let language: String?
    public let timecodeFrameRate: TimecodeFrameRate
    public let declarant: Party
    public let declarationDate: Date
    public let attachmentTypes: Set<AttachmentType>
    public let otherAttachmentDescription: String?

    public init(
        title: String,
        subtitle: String? = nil,
        producer: Party,
        directorOrPrincipal: Party,
        productionRuntime: MediaDuration,
        totalMusicRuntime: MediaDuration,
        productionYear: Int,
        knownOrFutureBroadcasts: String? = nil,
        containsAdditionalUndeclaredWorks: AdditionalWorksDeclaration,
        productionTypes: Set<ProductionType>,
        otherProductionTypeDescription: String? = nil,
        isanNumber: String? = nil,
        suisaRegistrationNumber: String? = nil,
        seriesTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        productionCountry: String? = nil,
        language: String? = nil,
        timecodeFrameRate: TimecodeFrameRate = .fps25,
        declarant: Party,
        declarationDate: Date,
        attachmentTypes: Set<AttachmentType> = [],
        otherAttachmentDescription: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.producer = producer
        self.directorOrPrincipal = directorOrPrincipal
        self.productionRuntime = productionRuntime
        self.totalMusicRuntime = totalMusicRuntime
        self.productionYear = productionYear
        self.knownOrFutureBroadcasts = knownOrFutureBroadcasts
        self.containsAdditionalUndeclaredWorks = containsAdditionalUndeclaredWorks
        self.productionTypes = productionTypes
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
        self.declarant = declarant
        self.declarationDate = declarationDate
        self.attachmentTypes = attachmentTypes
        self.otherAttachmentDescription = otherAttachmentDescription
    }
}

/// The SUISA form's "Does the film...contain any other musical works..."
/// tri-state field (SPEC.md §4.2). Small and tightly coupled to `Setup`
/// specifically, so it's co-located here rather than given its own file —
/// the same convention already used for `Timecode`/`TimecodeComponents`.
public enum AdditionalWorksDeclaration: Equatable, Sendable {
    case yes
    case no
    case notKnown
}
