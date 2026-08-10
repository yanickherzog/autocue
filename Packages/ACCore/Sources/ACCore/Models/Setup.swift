import Foundation

/// One per `Project` — the production-level header, mirroring the SUISA WA
/// Film form's top section almost 1:1 (SPEC.md §4.2).
///
/// No `id` field: `Setup` has no independent identity of its own outside the
/// `Project` it belongs to (1:1), the same "no `id` field, no `Identifiable`"
/// shape as `PostalAddress`/`Party` (`CLAUDE.md`, "Domain Model Value-Type
/// Conformances").
///
/// `producer`/`directorOrPrincipal`/`declarant` are `Party?`, not `Party`,
/// despite being required-for-export SUISA fields (SPEC.md §4.2). `Party` has
/// no case representing "none" — unlike a `String` (which can honestly start
/// as `""`) or a `Set` (which can honestly start as `[]`), there is no value
/// of `Party` that means "not yet chosen." A brand-new `Project` (`ROADMAP.md`
/// D6/T6.2) has no `Person`/`Label` in its directory yet to reference, so
/// these three fields must be representable as genuinely absent rather than
/// forced to reference a fabricated placeholder right-holder. Their
/// export-required-ness is enforced where every other required-but-absent
/// field in this type already is: `ValidateCueSheetUseCase` (`ROADMAP.md`
/// D11), not at construction time. See `docs/DECISIONS.md` for the full
/// record of this correction, made during D6 planning.
public struct Setup: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let producer: Party?
    public let directorOrPrincipal: Party?
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
    public let declarant: Party?
    public let declarationDate: Date
    public let attachmentTypes: Set<AttachmentType>
    public let otherAttachmentDescription: String?
    /// "Beitrag" — not on the physical SUISA form; a real field from the
    /// original product brief found missing from this schema during D7
    /// planning, added per `docs/DECISIONS.md`. Export-required-ness
    /// unresolved — see `ExploitationType`'s doc comment.
    public let beitrag: String?
    /// "Verwertung" — see `ExploitationType`.
    public let exploitationTypes: Set<ExploitationType>
    public let otherExploitationTypeDescription: String?
    /// "Sendedatum" — see `BroadcastDetails`. Deliberately separate from
    /// `knownOrFutureBroadcasts`, not a replacement for it.
    public let broadcastDetails: BroadcastDetails?

    public init(
        title: String,
        subtitle: String? = nil,
        producer: Party? = nil,
        directorOrPrincipal: Party? = nil,
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
        declarant: Party? = nil,
        declarationDate: Date,
        attachmentTypes: Set<AttachmentType> = [],
        otherAttachmentDescription: String? = nil,
        beitrag: String? = nil,
        exploitationTypes: Set<ExploitationType> = [],
        otherExploitationTypeDescription: String? = nil,
        broadcastDetails: BroadcastDetails? = nil
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
        self.beitrag = beitrag
        self.exploitationTypes = exploitationTypes
        self.otherExploitationTypeDescription = otherExploitationTypeDescription
        self.broadcastDetails = broadcastDetails
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

public extension Setup {
    /// Returns a copy of this `Setup` with the given fields overridden — a
    /// convenience for form-editing UI (`ROADMAP.md` D7's `SetupView`) over
    /// an otherwise fully-immutable (`let`-only) value type, where
    /// reconstructing the full memberwise initializer by hand for every
    /// single field edit across ~24 form fields would be impractical. Not a
    /// mutation — `self` is untouched; the caller adopts the returned value.
    ///
    /// **Every parameter defaults to `nil`, meaning "leave unchanged."**
    /// Fields that are themselves `Optional` on `Setup` (e.g. `subtitle`)
    /// take a *double*-optional parameter here (`String??`) so "don't touch
    /// this field" (outer `nil`, the default) is distinguishable from "set
    /// this field to `nil`" (`.some(nil)`) — the same ambiguity `Dictionary`'s
    /// own APIs face and resolve the same way.
    func updating(
        title: String? = nil,
        subtitle: String?? = nil,
        producer: Party?? = nil,
        directorOrPrincipal: Party?? = nil,
        productionRuntime: MediaDuration? = nil,
        totalMusicRuntime: MediaDuration? = nil,
        productionYear: Int? = nil,
        knownOrFutureBroadcasts: String?? = nil,
        containsAdditionalUndeclaredWorks: AdditionalWorksDeclaration? = nil,
        productionTypes: Set<ProductionType>? = nil,
        otherProductionTypeDescription: String?? = nil,
        isanNumber: String?? = nil,
        suisaRegistrationNumber: String?? = nil,
        seriesTitle: String?? = nil,
        seasonNumber: Int?? = nil,
        episodeNumber: Int?? = nil,
        episodeTitle: String?? = nil,
        productionCountry: String?? = nil,
        language: String?? = nil,
        timecodeFrameRate: TimecodeFrameRate? = nil,
        declarant: Party?? = nil,
        declarationDate: Date? = nil,
        attachmentTypes: Set<AttachmentType>? = nil,
        otherAttachmentDescription: String?? = nil,
        beitrag: String?? = nil,
        exploitationTypes: Set<ExploitationType>? = nil,
        otherExploitationTypeDescription: String?? = nil,
        broadcastDetails: BroadcastDetails?? = nil
    ) -> Setup {
        Setup(
            title: title ?? self.title,
            subtitle: subtitle ?? self.subtitle,
            producer: producer ?? self.producer,
            directorOrPrincipal: directorOrPrincipal ?? self.directorOrPrincipal,
            productionRuntime: productionRuntime ?? self.productionRuntime,
            totalMusicRuntime: totalMusicRuntime ?? self.totalMusicRuntime,
            productionYear: productionYear ?? self.productionYear,
            knownOrFutureBroadcasts: knownOrFutureBroadcasts ?? self.knownOrFutureBroadcasts,
            containsAdditionalUndeclaredWorks: containsAdditionalUndeclaredWorks ?? self
                .containsAdditionalUndeclaredWorks,
            productionTypes: productionTypes ?? self.productionTypes,
            otherProductionTypeDescription: otherProductionTypeDescription ?? self.otherProductionTypeDescription,
            isanNumber: isanNumber ?? self.isanNumber,
            suisaRegistrationNumber: suisaRegistrationNumber ?? self.suisaRegistrationNumber,
            seriesTitle: seriesTitle ?? self.seriesTitle,
            seasonNumber: seasonNumber ?? self.seasonNumber,
            episodeNumber: episodeNumber ?? self.episodeNumber,
            episodeTitle: episodeTitle ?? self.episodeTitle,
            productionCountry: productionCountry ?? self.productionCountry,
            language: language ?? self.language,
            timecodeFrameRate: timecodeFrameRate ?? self.timecodeFrameRate,
            declarant: declarant ?? self.declarant,
            declarationDate: declarationDate ?? self.declarationDate,
            attachmentTypes: attachmentTypes ?? self.attachmentTypes,
            otherAttachmentDescription: otherAttachmentDescription ?? self.otherAttachmentDescription,
            beitrag: beitrag ?? self.beitrag,
            exploitationTypes: exploitationTypes ?? self.exploitationTypes,
            otherExploitationTypeDescription: otherExploitationTypeDescription ?? self.otherExploitationTypeDescription,
            broadcastDetails: broadcastDetails ?? self.broadcastDetails
        )
    }
}

/// One of `Setup`'s §4.2-required-for-export fields that has no honest
/// "not yet entered" value distinguishable from a real answer — see
/// `Setup.missingRequiredFields`'s doc comment for the full reasoning behind
/// exactly these seven and no others.
public enum SetupRequiredField: Equatable, Sendable {
    case title
    case producer
    case directorOrPrincipal
    case productionRuntime
    case productionYear
    case productionTypes
    case declarant
}

public extension Setup {
    /// Every §4.2-required-for-export field currently unset on this `Setup`,
    /// checked against its own currently-empty/zero *sentinel* value — the
    /// same distinction `docs/DECISIONS.md`'s "`Setup`'s three `Party` fields
    /// become optional" field-by-field audit already drew between "has an
    /// honest not-yet-entered value" and "doesn't." A pure computed property,
    /// the same shape as `PostalAddress.isComplete` — no Repository
    /// dependency, safe to call from a ViewModel with no I/O.
    ///
    /// **Not every §4.2-required field is checked here — only the ones where
    /// "still at its default" reliably means "not yet entered," not "a real,
    /// already-confirmed answer that happens to look empty":**
    /// - `totalMusicRuntime` is excluded: it's a *derived* value (SPEC.md
    ///   §4.14, `RecalculateTotalMusicRuntimeUseCase`), not something the user
    ///   enters on this screen — `.zero` is the honestly-correct value for a
    ///   `Project` with no `Cue`s yet (true for every `Setup` until D9/D10
    ///   land), not a sign of incompleteness.
    /// - `containsAdditionalUndeclaredWorks` is excluded: `.notKnown` is
    ///   itself a real, SUISA-sanctioned answer to this question (per the
    ///   field-by-field audit referenced above), indistinguishable at the
    ///   type level from "user reviewed and confirmed unknown" vs. "user
    ///   hasn't touched this yet" — flagging it would be a false positive on
    ///   a `Setup` that's actually fully reviewed.
    /// - `declarationDate`/`timecodeFrameRate` are excluded: both have a
    ///   SPEC-sanctioned default (today's date; `.fps25`) that's already a
    ///   real, usable value, not a placeholder standing in for missing data —
    ///   `timecodeFrameRate` is app-internal only and never exported at all.
    ///
    /// Reused by `ROADMAP.md` D11's `ValidateCueSheetUseCase` rather than
    /// duplicated there — this is the "Setup completeness" half of that
    /// Use Case's aggregate check, built here first because `SetupViewModel`
    /// (D7) needs it before D11 exists.
    var missingRequiredFields: [SetupRequiredField] {
        var missing: [SetupRequiredField] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append(.title)
        }
        if producer == nil {
            missing.append(.producer)
        }
        if directorOrPrincipal == nil {
            missing.append(.directorOrPrincipal)
        }
        if productionRuntime == .zero {
            missing.append(.productionRuntime)
        }
        if productionYear == 0 {
            missing.append(.productionYear)
        }
        if productionTypes.isEmpty {
            missing.append(.productionTypes)
        }
        if declarant == nil {
            missing.append(.declarant)
        }
        return missing
    }
}
