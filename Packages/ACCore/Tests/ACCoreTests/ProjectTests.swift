@testable import ACCore
import XCTest

final class ProjectTests: XCTestCase {
    private static func makeSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeAudioAsset() -> AudioAsset {
        AudioAsset(
            originalFileName: "reel1.wav",
            securityScopedBookmark: Data([0x01, 0x02]),
            duration: MediaDuration(seconds: 3600),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeProject(
        name: String = "Reel One",
        audioAsset: AudioAsset? = nil,
        waveformPeaks: WaveformPeaks? = nil,
        cues: [Cue] = [],
        people: [Person] = [],
        labels: [Label] = []
    ) -> Project {
        Project(
            name: name,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
            waveformPeaks: waveformPeaks,
            setup: makeSetup(),
            cues: cues,
            people: people,
            labels: labels
        )
    }

    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Self.makeProject()
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingID_makesOtherwiseIdenticalProjectsUnequal() {
        XCTAssertNotEqual(
            Project(
                id: UUID(),
                name: "Reel One",
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                setup: Self.makeSetup()
            ),
            Project(
                id: UUID(),
                name: "Reel One",
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                setup: Self.makeSetup()
            )
        )
    }

    func test_audioAssetAndWaveformPeaks_defaultToNilWhenOmitted() {
        let project = Self.makeProject()
        XCTAssertNil(project.audioAsset)
        XCTAssertNil(project.waveformPeaks)
    }

    func test_cuesPeopleAndLabels_defaultToEmptyArraysWhenOmitted() {
        let project = Self.makeProject()
        XCTAssertTrue(project.cues.isEmpty)
        XCTAssertTrue(project.people.isEmpty)
        XCTAssertTrue(project.labels.isEmpty)
    }

    func test_composesAudioAssetAndWaveformPeaksAsSiblingOptionals() {
        let audioAsset = Self.makeAudioAsset()
        let waveformPeaks = WaveformPeaks(
            audioAssetID: audioAsset.id,
            resolution: 4096,
            buckets: Array(repeating: WaveformPeakBucket(min: -1, max: 1), count: 4096)
        )
        let project = Self.makeProject(audioAsset: audioAsset, waveformPeaks: waveformPeaks)

        XCTAssertEqual(project.audioAsset, audioAsset)
        XCTAssertEqual(project.waveformPeaks, waveformPeaks)
        XCTAssertEqual(project.waveformPeaks?.audioAssetID, project.audioAsset?.id)
    }

    func test_composesCuesPeopleAndLabels() {
        let person = Person(firstName: "Anna", lastName: "Muster")
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let cue = Cue(title: "Alpine Theme", duration: MediaDuration(seconds: 120), rightHolders: [], source: .manual)
        let project = Self.makeProject(cues: [cue], people: [person], labels: [label])

        XCTAssertEqual(project.cues, [cue])
        XCTAssertEqual(project.people, [person])
        XCTAssertEqual(project.labels, [label])
    }
}
