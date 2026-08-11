import ACCore
import Foundation

/// A fully-populated `Project` fixture — every optional field set at least
/// once somewhere in the graph (a `Person` with an address, a `Label`, an
/// `AudioAsset` with embedded markers and broadcast-wave metadata,
/// `WaveformPeaks`, more than one `Cue` each with more than one
/// `CueRightHolder`) — so the round-trip test in `ProjectRoundTripTests`
/// actually exercises every mapper, not just the required-fields path.
///
/// Kept local to `ACPersistenceTests` for now, per `CLAUDE.md` rule 7 — this
/// is the first package that needs a fixture like this; promote to
/// `ACTestSupport` only once a second package genuinely needs the same one.
enum ProjectFixture {
    private struct Identities {
        let composerID = UUID()
        let publisherLabelID = UUID()
        let producerPersonID = UUID()
        let directorPersonID = UUID()
        let declarantLabelID = UUID()
        let performerID = UUID()
    }

    static func make() -> Project {
        let ids = Identities()
        let audioAsset = makeAudioAsset()

        return Project(
            name: "great-swiss-film-2026",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_100),
            audioAsset: audioAsset,
            waveformPeaks: makeWaveformPeaks(audioAssetID: audioAsset.id),
            setup: makeFullSetup(ids: ids),
            cues: makeCues(ids: ids),
            people: makePeople(ids: ids),
            labels: makeLabels(ids: ids)
        )
    }

    /// A minimal-but-valid fixture — every required field, every optional
    /// field left `nil`/empty — for tests that don't need the full graph.
    static func makeMinimal(id: UUID = UUID(), name: String = "minimal-project") -> Project {
        let producerID = UUID()
        return Project(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            setup: Setup(
                title: "Minimal",
                producer: [.person(producerID)],
                directorOrPrincipal: [.person(producerID)],
                productionRuntime: MediaDuration(seconds: 60),
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.other],
                otherProductionTypeDescription: "n/a",
                declarant: .person(producerID),
                declarationDate: Date(timeIntervalSince1970: 1_699_000_000)
            )
        )
    }

    // MARK: - People / Labels

    private static func makePeople(ids: Identities) -> [Person] {
        let composer = Person(
            id: ids.composerID,
            firstName: "Ada",
            lastName: "Lovelace",
            ipiNumber: "00123456789",
            address: PostalAddress(
                street: "Bahnhofstrasse 1",
                postalCode: "8001",
                city: "Zürich",
                country: "Switzerland"
            ),
            email: "ada@example.com",
            swissPerformNumber: "SP-42"
        )
        let producer = Person(id: ids.producerPersonID, firstName: "Grace", lastName: "Hopper")
        let director = Person(id: ids.directorPersonID, firstName: "Alan", lastName: "Turing")
        let performer = Person(id: ids.performerID, firstName: "Nina", lastName: "Simone")
        return [composer, producer, director, performer]
    }

    private static func makeLabels(ids: Identities) -> [Label] {
        let publisherLabel = Label(
            id: ids.publisherLabelID,
            name: "Helvetic Music Publishing",
            address: PostalAddress(
                street: "Rue du Rhône 10",
                postalCode: "1204",
                city: "Genève",
                country: "Switzerland"
            ),
            ipiNumber: "00987654321",
            kind: .publisher
        )
        let declarantLabel = Label(
            id: ids.declarantLabelID,
            name: "AutoCue Productions SA",
            address: PostalAddress(
                street: "Via Nassa 5",
                postalCode: "6900",
                city: "Lugano",
                country: "Switzerland"
            )
        )
        return [publisherLabel, declarantLabel]
    }

    // MARK: - Cues

    private static func makeCues(ids: Identities) -> [Cue] {
        [makeOpeningThemeCue(ids: ids), makeEndCreditsCue(ids: ids)]
    }

    private static func makeOpeningThemeCue(ids: Identities) -> Cue {
        Cue(
            title: "Opening Theme",
            workNumber: "W-001",
            duration: MediaDuration(seconds: 125.5),
            rightHolders: [
                CueRightHolder(
                    party: .person(ids.composerID),
                    role: .composer,
                    performanceBroadcastShare: decimal("60.00"),
                    mechanicalRightsShare: decimal("60.00")
                ),
                CueRightHolder(
                    party: .label(ids.publisherLabelID),
                    role: .publisher,
                    performanceBroadcastShare: decimal("40.00"),
                    mechanicalRightsShare: decimal("40.00"),
                    publishingContractAttached: true
                ),
                // .performer is excluded from the 100%-sum checks
                // (ValidateCueRightHolderSharesUseCase, docs/DECISIONS.md) —
                // its 0/0 shares here are deliberately meaningless, not a
                // fixture oversight, and don't affect the 60/40 split above.
                CueRightHolder(
                    party: .person(ids.performerID),
                    role: .performer,
                    performanceBroadcastShare: 0,
                    mechanicalRightsShare: 0
                ),
            ],
            isArrangementOfProtectedOriginal: false,
            source: .embeddedMarker,
            startTimecode: Timecode(offsetSeconds: 12.0),
            notes: "Cold open"
        )
    }

    private static func makeEndCreditsCue(ids: Identities) -> Cue {
        Cue(
            title: "End Credits",
            duration: MediaDuration(seconds: 90.0),
            rightHolders: [
                CueRightHolder(
                    party: .person(ids.composerID),
                    role: .composer,
                    performanceBroadcastShare: decimal("33.33"),
                    mechanicalRightsShare: decimal("33.33")
                ),
                CueRightHolder(
                    party: .person(ids.producerPersonID),
                    role: .arranger,
                    performanceBroadcastShare: decimal("33.33"),
                    mechanicalRightsShare: decimal("33.33"),
                    arrangementAuthorizationAttached: true
                ),
                CueRightHolder(
                    party: .label(ids.publisherLabelID),
                    role: .publisher,
                    performanceBroadcastShare: decimal("33.34"),
                    mechanicalRightsShare: decimal("33.34"),
                    publishingContractAttached: true
                ),
            ],
            isArrangementOfProtectedOriginal: true,
            source: .manual
        )
    }

    // MARK: - AudioAsset / WaveformPeaks

    private static func makeAudioAsset() -> AudioAsset {
        AudioAsset(
            originalFileName: "production_mix.wav",
            securityScopedBookmark: Data([0x01, 0x02, 0x03, 0x04]),
            duration: MediaDuration(seconds: 3600.25),
            sampleRate: 48000.0,
            channelCount: 2,
            bitDepth: 24,
            embeddedMarkers: [
                EmbeddedMarker(position: Timecode(offsetSeconds: 12.0), label: "Cue 1 In", note: "from editor"),
                EmbeddedMarker(position: Timecode(offsetSeconds: 200.0), label: "Cue 2 In"),
            ],
            broadcastWaveMetadata: BroadcastWaveMetadata(
                description: "Final mix",
                originator: "Pro Tools",
                originatorReference: "PT-REF-001",
                originationDate: Date(timeIntervalSince1970: 1_700_000_000),
                timeReferenceSamples: 48_000_000
            ),
            importedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
    }

    private static func makeWaveformPeaks(audioAssetID: AudioAsset.ID) -> WaveformPeaks {
        WaveformPeaks(
            audioAssetID: audioAssetID,
            resolution: 8,
            buckets: (0 ..< 8).map { index in
                WaveformPeakBucket(min: Float(-index) / 10.0, max: Float(index) / 10.0)
            }
        )
    }

    // MARK: - Setup

    private static func makeFullSetup(ids: Identities) -> Setup {
        Setup(
            title: "The Great Swiss Film",
            subtitle: "A Documentary",
            producer: [.person(ids.producerPersonID)],
            directorOrPrincipal: [.person(ids.directorPersonID)],
            productionRuntime: MediaDuration(seconds: 5400.0),
            totalMusicRuntime: MediaDuration(seconds: 215.5),
            productionYear: 2026,
            knownOrFutureBroadcasts: "SRF, RTS",
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm, .tvBroadcast],
            otherProductionTypeDescription: nil,
            isanNumber: "ISAN-0000-0000-1",
            suisaRegistrationNumber: nil,
            seriesTitle: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            episodeTitle: nil,
            productionCountry: "Switzerland",
            language: "de",
            timecodeFrameRate: .fps25,
            timecodeStart: Timecode(offsetSeconds: 35992),
            declarant: .label(ids.declarantLabelID),
            declarationDate: Date(timeIntervalSince1970: 1_700_001_000),
            attachmentTypes: [.score, .other],
            otherAttachmentDescription: "Cue sheet appendix",
            beitrag: "Bergwelt, Folge 5",
            exploitationTypes: [.tv, .festival],
            broadcastDetails: [
                BroadcastDetails(
                    broadcaster: "SRF",
                    programmeName: "Bergwelt",
                    date: Date(timeIntervalSince1970: 1_700_002_000)
                ),
            ]
        )
    }

    // MARK: - Helpers

    /// `guard let` rather than `Decimal(string:)!` — every call site below
    /// passes a compile-time-known-good literal, so this can only ever fail
    /// if the literal itself is malformed, which `preconditionFailure` makes
    /// exactly as loud as a force-unwrap crash would have, without tripping
    /// SwiftLint's `force_unwrapping` rule (`CONTRIBUTING.md` §8/§9).
    private static func decimal(_ value: String) -> Decimal {
        guard let decimal = Decimal(string: value) else {
            preconditionFailure("Invalid decimal literal in fixture: \(value)")
        }
        return decimal
    }
}
