import ACCore
import Foundation

/// Converts `ACCore.Setup` to/from `SetupEntity`. None of `Setup`'s enum
/// fields are `RawRepresentable`, so encoding to/from the `String` columns
/// SwiftData stores is done with explicit switches here rather than
/// `.rawValue` — deliberately not adding `RawRepresentable` conformance to
/// the domain enums just to make this file shorter (that conformance would
/// have no other caller and would be exactly the kind of premature
/// convenience `CLAUDE.md` rule 7 warns against).
enum SetupMapper {
    static func toEntity(_ setup: Setup) -> SetupEntity {
        SetupEntity(
            title: setup.title,
            subtitle: setup.subtitle,
            producerPartyKind: PartyMapper.kind(for: setup.producer),
            producerPartyID: PartyMapper.id(for: setup.producer),
            directorPartyKind: PartyMapper.kind(for: setup.directorOrPrincipal),
            directorPartyID: PartyMapper.id(for: setup.directorOrPrincipal),
            productionRuntimeSeconds: setup.productionRuntime.seconds,
            totalMusicRuntimeSeconds: setup.totalMusicRuntime.seconds,
            productionYear: setup.productionYear,
            knownOrFutureBroadcasts: setup.knownOrFutureBroadcasts,
            containsAdditionalUndeclaredWorks: rawValue(for: setup.containsAdditionalUndeclaredWorks),
            productionTypesRawValues: setup.productionTypes.map(rawValue(for:)).sorted(),
            otherProductionTypeDescription: setup.otherProductionTypeDescription,
            isanNumber: setup.isanNumber,
            suisaRegistrationNumber: setup.suisaRegistrationNumber,
            seriesTitle: setup.seriesTitle,
            seasonNumber: setup.seasonNumber,
            episodeNumber: setup.episodeNumber,
            episodeTitle: setup.episodeTitle,
            productionCountry: setup.productionCountry,
            language: setup.language,
            timecodeFrameRate: rawValue(for: setup.timecodeFrameRate),
            declarantPartyKind: PartyMapper.kind(for: setup.declarant),
            declarantPartyID: PartyMapper.id(for: setup.declarant),
            declarationDate: setup.declarationDate,
            attachmentTypesRawValues: setup.attachmentTypes.map(rawValue(for:)).sorted(),
            otherAttachmentDescription: setup.otherAttachmentDescription
        )
    }

    static func toDomain(_ entity: SetupEntity) throws -> Setup {
        try Setup(
            title: entity.title,
            subtitle: entity.subtitle,
            producer: PartyMapper.party(kind: entity.producerPartyKind, id: entity.producerPartyID),
            directorOrPrincipal: PartyMapper.party(kind: entity.directorPartyKind, id: entity.directorPartyID),
            productionRuntime: MediaDuration(seconds: entity.productionRuntimeSeconds),
            totalMusicRuntime: MediaDuration(seconds: entity.totalMusicRuntimeSeconds),
            productionYear: entity.productionYear,
            knownOrFutureBroadcasts: entity.knownOrFutureBroadcasts,
            containsAdditionalUndeclaredWorks: additionalWorksDeclaration(
                from: entity.containsAdditionalUndeclaredWorks
            ),
            productionTypes: Set(entity.productionTypesRawValues.map(productionType(from:))),
            otherProductionTypeDescription: entity.otherProductionTypeDescription,
            isanNumber: entity.isanNumber,
            suisaRegistrationNumber: entity.suisaRegistrationNumber,
            seriesTitle: entity.seriesTitle,
            seasonNumber: entity.seasonNumber,
            episodeNumber: entity.episodeNumber,
            episodeTitle: entity.episodeTitle,
            productionCountry: entity.productionCountry,
            language: entity.language,
            timecodeFrameRate: timecodeFrameRate(from: entity.timecodeFrameRate),
            declarant: PartyMapper.party(kind: entity.declarantPartyKind, id: entity.declarantPartyID),
            declarationDate: entity.declarationDate,
            attachmentTypes: Set(entity.attachmentTypesRawValues.map(attachmentType(from:))),
            otherAttachmentDescription: entity.otherAttachmentDescription
        )
    }

    // MARK: - AdditionalWorksDeclaration

    private static func rawValue(for value: AdditionalWorksDeclaration) -> String {
        switch value {
        case .yes: "yes"
        case .no: "no"
        case .notKnown: "notKnown"
        }
    }

    private static func additionalWorksDeclaration(from rawValue: String) throws -> AdditionalWorksDeclaration {
        switch rawValue {
        case "yes": .yes
        case "no": .no
        case "notKnown": .notKnown
        default: throw MappingError.unknownRawValue(type: "AdditionalWorksDeclaration", rawValue: rawValue)
        }
    }

    // MARK: - ProductionType

    /// A lookup table, not a 14-case `switch`, specifically to stay under
    /// SwiftLint's cyclomatic-complexity threshold — `ProductionType` has the
    /// most cases of any enum this mapper handles, and a `switch` in both
    /// directions tripped `cyclomatic_complexity` (`CONTRIBUTING.md` §8).
    /// `CaseIterable` (already a `ProductionType` conformance) is what makes
    /// building the reverse table from the forward one safe — no case can be
    /// silently missing.
    private static let productionTypeRawValues: [ProductionType: String] = [
        .featureFilm: "featureFilm",
        .shortFilmCinema: "shortFilmCinema",
        .tvFeatureFilm: "tvFeatureFilm",
        .tvShotFilm: "tvShotFilm",
        .series: "series",
        .documentaryFilm: "documentaryFilm",
        .tvBroadcast: "tvBroadcast",
        .leadInStationID: "leadInStationID",
        .educationalFilm: "educationalFilm",
        .commercial: "commercial",
        .corporateFilm: "corporateFilm",
        .videoClip: "videoClip",
        .multimedia: "multimedia",
        .other: "other",
    ]

    private static let productionTypesByRawValue: [String: ProductionType] = Dictionary(
        uniqueKeysWithValues: productionTypeRawValues.map { ($1, $0) }
    )

    private static func rawValue(for value: ProductionType) -> String {
        // Force-unwrap is safe: `productionTypeRawValues` is a fixed literal
        // covering every `ProductionType` case, verified by
        // `SetupMapperTests`'s exhaustiveness test, not by `CaseIterable`
        // itself (a dictionary literal isn't compiler-checked for coverage).
        guard let rawValue = productionTypeRawValues[value] else {
            preconditionFailure("productionTypeRawValues is missing a case: \(value)")
        }
        return rawValue
    }

    private static func productionType(from rawValue: String) throws -> ProductionType {
        guard let value = productionTypesByRawValue[rawValue] else {
            throw MappingError.unknownRawValue(type: "ProductionType", rawValue: rawValue)
        }
        return value
    }

    // MARK: - AttachmentType

    private static func rawValue(for value: AttachmentType) -> String {
        switch value {
        case .score: "score"
        case .agreement: "agreement"
        case .soundOrVideoCarrier: "soundOrVideoCarrier"
        case .other: "other"
        }
    }

    private static func attachmentType(from rawValue: String) throws -> AttachmentType {
        switch rawValue {
        case "score": .score
        case "agreement": .agreement
        case "soundOrVideoCarrier": .soundOrVideoCarrier
        case "other": .other
        default: throw MappingError.unknownRawValue(type: "AttachmentType", rawValue: rawValue)
        }
    }

    // MARK: - TimecodeFrameRate

    private static func rawValue(for value: TimecodeFrameRate) -> String {
        switch value {
        case .fps24: "fps24"
        case .fps25: "fps25"
        case .fps29_97NonDrop: "fps29_97NonDrop"
        case .fps29_97Drop: "fps29_97Drop"
        case .fps30: "fps30"
        }
    }

    private static func timecodeFrameRate(from rawValue: String) throws -> TimecodeFrameRate {
        switch rawValue {
        case "fps24": .fps24
        case "fps25": .fps25
        case "fps29_97NonDrop": .fps29_97NonDrop
        case "fps29_97Drop": .fps29_97Drop
        case "fps30": .fps30
        default: throw MappingError.unknownRawValue(type: "TimecodeFrameRate", rawValue: rawValue)
        }
    }
}
