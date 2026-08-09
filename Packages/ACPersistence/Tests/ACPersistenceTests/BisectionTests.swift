@testable import ACCore
@testable import ACPersistence
import SwiftData
import XCTest

/// THROWAWAY bisection harness — not part of D4's real test suite, to be
/// deleted once the actual crash-triggering fixture complexity is isolated.
/// Not a fix attempt: this reports which stage crashes, nothing more.
///
/// Each stage adds exactly one more piece of complexity on top of the
/// previous stage, doing the identical round-trip (map -> insert -> save ->
/// fetch -> map back) as `ProjectRoundTripTests.test_arrayOrderSurvivesRoundTrip`.
/// Named `test_stage1_`...`test_stage7_` so alphabetical XCTest execution
/// order matches stage order, and this class is named to sort before the
/// rest of the target's test classes alphabetically, so it runs first and
/// in isolation. Once the crashing process dies, every later stage simply
/// never runs — the last "started"/"passed" line printed before the crash
/// is the signal.
final class BisectionTests: XCTestCase {
    private func roundTrip(_ project: Project) throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(ProjectMapper.toEntity(project))
        try context.save()
        let fetchedEntities = try context.fetch(FetchDescriptor<ProjectEntity>())
        _ = try ProjectMapper.toDomain(XCTUnwrap(fetchedEntities.first))
    }

    private func makeSetup() -> Setup {
        let partyID = UUID()
        return Setup(
            title: "Bisection",
            producer: .person(partyID),
            directorOrPrincipal: .person(partyID),
            productionRuntime: MediaDuration(seconds: 60),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.other],
            otherProductionTypeDescription: "n/a",
            declarant: .person(partyID),
            declarationDate: Date(timeIntervalSince1970: 1_699_000_000)
        )
    }

    /// Stage 1: one `Cue`, zero `CueRightHolder`s, no people/labels/audioAsset.
    func test_stage1_oneCueZeroRightHolders() throws {
        let cue = Cue(
            title: "Cue 1",
            duration: MediaDuration(seconds: 60),
            rightHolders: [],
            source: .manual
        )
        let project = Project(
            name: "stage1",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            setup: makeSetup(),
            cues: [cue]
        )
        try roundTrip(project)
    }

    /// Stage 2: the Cue has one `CueRightHolder`.
    func test_stage2_oneCueOneRightHolder() throws {
        let rightHolder = CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: Decimal(100),
            mechanicalRightsShare: Decimal(100)
        )
        let cue = Cue(
            title: "Cue 1",
            duration: MediaDuration(seconds: 60),
            rightHolders: [rightHolder],
            source: .manual
        )
        let project = Project(
            name: "stage2",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            setup: makeSetup(),
            cues: [cue]
        )
        try roundTrip(project)
    }

    /// Stage 3: add one `Person`, referenced by that `CueRightHolder`'s party.
    func test_stage3_addPerson() throws {
        let personID = UUID()
        let person = Person(id: personID, firstName: "Ada", lastName: "Lovelace")
        let rightHolder = CueRightHolder(
            party: .person(personID),
            role: .composer,
            performanceBroadcastShare: Decimal(100),
            mechanicalRightsShare: Decimal(100)
        )
        let cue = Cue(
            title: "Cue 1",
            duration: MediaDuration(seconds: 60),
            rightHolders: [rightHolder],
            source: .manual
        )
        let project = Project(
            name: "stage3",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            setup: makeSetup(),
            cues: [cue],
            people: [person]
        )
        try roundTrip(project)
    }

    /// Stage 4: add one `Label` too.
    func test_stage4_addLabel() throws {
        let personID = UUID()
        let person = Person(id: personID, firstName: "Ada", lastName: "Lovelace")
        let label = Label(
            name: "Test Label",
            address: PostalAddress(street: "Street", postalCode: "0000", city: "City", country: "Country")
        )
        let rightHolder = CueRightHolder(
            party: .person(personID),
            role: .composer,
            performanceBroadcastShare: Decimal(100),
            mechanicalRightsShare: Decimal(100)
        )
        let cue = Cue(
            title: "Cue 1",
            duration: MediaDuration(seconds: 60),
            rightHolders: [rightHolder],
            source: .manual
        )
        let project = Project(
            name: "stage4",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            setup: makeSetup(),
            cues: [cue],
            people: [person],
            labels: [label]
        )
        try roundTrip(project)
    }

    /// Stage 5: add an `AudioAsset` with one `EmbeddedMarker`.
    func test_stage5_addAudioAssetWithMarker() throws {
        let personID = UUID()
        let person = Person(id: personID, firstName: "Ada", lastName: "Lovelace")
        let label = Label(
            name: "Test Label",
            address: PostalAddress(street: "Street", postalCode: "0000", city: "City", country: "Country")
        )
        let rightHolder = CueRightHolder(
            party: .person(personID),
            role: .composer,
            performanceBroadcastShare: Decimal(100),
            mechanicalRightsShare: Decimal(100)
        )
        let cue = Cue(
            title: "Cue 1",
            duration: MediaDuration(seconds: 60),
            rightHolders: [rightHolder],
            source: .manual
        )
        let audioAsset = AudioAsset(
            originalFileName: "test.wav",
            securityScopedBookmark: Data([0x01]),
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 1,
            bitDepth: 16,
            embeddedMarkers: [EmbeddedMarker(position: Timecode(offsetSeconds: 1))],
            importedAt: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let project = Project(
            name: "stage5",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            audioAsset: audioAsset,
            setup: makeSetup(),
            cues: [cue],
            people: [person],
            labels: [label]
        )
        try roundTrip(project)
    }

    /// Stage 6: add `WaveformPeaks`.
    func test_stage6_addWaveformPeaks() throws {
        let personID = UUID()
        let person = Person(id: personID, firstName: "Ada", lastName: "Lovelace")
        let label = Label(
            name: "Test Label",
            address: PostalAddress(street: "Street", postalCode: "0000", city: "City", country: "Country")
        )
        let rightHolder = CueRightHolder(
            party: .person(personID),
            role: .composer,
            performanceBroadcastShare: Decimal(100),
            mechanicalRightsShare: Decimal(100)
        )
        let cue = Cue(
            title: "Cue 1",
            duration: MediaDuration(seconds: 60),
            rightHolders: [rightHolder],
            source: .manual
        )
        let audioAsset = AudioAsset(
            originalFileName: "test.wav",
            securityScopedBookmark: Data([0x01]),
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 1,
            bitDepth: 16,
            embeddedMarkers: [EmbeddedMarker(position: Timecode(offsetSeconds: 1))],
            importedAt: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let waveformPeaks = WaveformPeaks(
            audioAssetID: audioAsset.id,
            resolution: 2,
            buckets: [
                WaveformPeakBucket(min: -0.1, max: 0.1),
                WaveformPeakBucket(min: -0.2, max: 0.2),
            ]
        )
        let project = Project(
            name: "stage6",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            audioAsset: audioAsset,
            waveformPeaks: waveformPeaks,
            setup: makeSetup(),
            cues: [cue],
            people: [person],
            labels: [label]
        )
        try roundTrip(project)
    }

    /// Stage 7: the full original fixture, unchanged.
    func test_stage7_fullOriginalFixture() throws {
        try roundTrip(ProjectFixture.make())
    }
}
