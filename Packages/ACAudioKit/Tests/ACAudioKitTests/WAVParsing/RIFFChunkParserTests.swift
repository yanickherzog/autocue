@testable import ACAudioKit
import ACCore
import XCTest

final class RIFFChunkParserTests: XCTestCase {
    private var fixtureURLs: [URL] = []

    override func tearDown() {
        for url in fixtureURLs {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureURLs = []
        super.tearDown()
    }

    private func makeFixture(
        sampleRate: Double = 48000,
        cuePoints: [WAVFixtureBuilder.CuePointFixture] = [],
        broadcastExtension: WAVFixtureBuilder.BroadcastExtensionFixture? = nil
    ) throws -> URL {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        try WAVFixtureBuilder.writeWAVFile(
            sampleRate: sampleRate,
            channelSamples: [[Float](repeating: 0, count: 1000)],
            cuePoints: cuePoints,
            broadcastExtension: broadcastExtension,
            to: url
        )
        fixtureURLs.append(url)
        return url
    }

    func test_extractsAllMarkers_withSampleAccuratePositions() throws {
        let sampleRate = 48000.0
        let url = try makeFixture(sampleRate: sampleRate, cuePoints: [
            .init(id: 1, sampleOffset: 0, label: "Cue One", note: "Opening"),
            .init(id: 2, sampleOffset: 24000, label: "Cue Two", note: nil),
            .init(id: 3, sampleOffset: 47999, label: nil, note: "Note only"),
        ])

        let result = try RIFFChunkParser.parse(url: url)

        XCTAssertEqual(result.embeddedMarkers.count, 3)

        let first = result.embeddedMarkers[0]
        XCTAssertEqual(first.label, "Cue One")
        XCTAssertEqual(first.note, "Opening")
        XCTAssertEqual(first.position.offsetSeconds, 0, accuracy: 0.0001)

        let second = result.embeddedMarkers[1]
        XCTAssertEqual(second.label, "Cue Two")
        XCTAssertNil(second.note)
        XCTAssertEqual(second.position.offsetSeconds, 24000.0 / sampleRate, accuracy: 0.0001)

        let third = result.embeddedMarkers[2]
        XCTAssertNil(third.label)
        XCTAssertEqual(third.note, "Note only")
        XCTAssertEqual(third.position.offsetSeconds, (48000.0 - 1) / sampleRate, accuracy: 0.0001)
    }

    func test_returnsEmptyResult_notCrashOrThrow_whenNoMarkerChunksPresent() throws {
        let url = try makeFixture()

        let result = try RIFFChunkParser.parse(url: url)

        XCTAssertEqual(result.embeddedMarkers, [])
        XCTAssertNil(result.broadcastWaveMetadata)
    }

    func test_extractsBroadcastWaveMetadata_whenBextChunkPresent() throws {
        let url = try makeFixture(broadcastExtension: .init(
            description: "Test recording",
            originator: "AutoCue Test Rig",
            originatorReference: "REF123",
            originationDate: "2026-08-12",
            originationTime: "14:30:00",
            timeReferenceSamples: 123_456_789
        ))

        let result = try RIFFChunkParser.parse(url: url)

        let metadata = try XCTUnwrap(result.broadcastWaveMetadata)
        XCTAssertEqual(metadata.description, "Test recording")
        XCTAssertEqual(metadata.originator, "AutoCue Test Rig")
        XCTAssertEqual(metadata.originatorReference, "REF123")
        XCTAssertEqual(metadata.timeReferenceSamples, 123_456_789)
        XCTAssertNotNil(metadata.originationDate)
    }

    func test_bextAbsent_reportsNilBroadcastWaveMetadata() throws {
        let url = try makeFixture(cuePoints: [.init(id: 1, sampleOffset: 0, label: "Only a cue")])

        let result = try RIFFChunkParser.parse(url: url)

        XCTAssertNil(result.broadcastWaveMetadata)
        XCTAssertEqual(result.embeddedMarkers.count, 1)
    }

    func test_throws_forANonRIFFFile() throws {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        try Data("not a riff file at all".utf8).write(to: url)
        fixtureURLs.append(url)

        XCTAssertThrowsError(try RIFFChunkParser.parse(url: url)) { error in
            XCTAssertEqual(error as? RIFFChunkParserError, .notARIFFFile)
        }
    }

    /// The parser must never read the (potentially multi-gigabyte) `data`
    /// chunk's bytes into memory — only seek past it via its declared
    /// length. Not directly observable from outside without instrumenting
    /// the byte-level reads, so this test's real value is a large `data`
    /// chunk (relative to the tiny marker chunks) still parsing correctly
    /// and quickly — a naive "read everything" implementation would still
    /// pass functionally but this at least exercises a `data` chunk an order
    /// of magnitude larger than the marker chunks alongside them.
    func test_largeDataChunkIsSkipped_notReadIntoMemory() throws {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        try WAVFixtureBuilder.writeWAVFile(
            channelSamples: [[Float](repeating: 0, count: 500_000)],
            cuePoints: [.init(id: 9, sampleOffset: 500, label: "Found Past Data")],
            to: url
        )
        fixtureURLs.append(url)

        let result = try RIFFChunkParser.parse(url: url)
        XCTAssertEqual(result.embeddedMarkers.first?.label, "Found Past Data")
    }
}
