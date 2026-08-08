@testable import ACCore
import XCTest

final class AudioAssetTests: XCTestCase {
    private static func makeAsset(
        embeddedMarkers: [EmbeddedMarker] = [],
        broadcastWaveMetadata: BroadcastWaveMetadata? = nil
    ) -> AudioAsset {
        AudioAsset(
            originalFileName: "reel1.wav",
            securityScopedBookmark: Data([0x01, 0x02, 0x03]),
            duration: MediaDuration(seconds: 3600),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            embeddedMarkers: embeddedMarkers,
            broadcastWaveMetadata: broadcastWaveMetadata,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Self.makeAsset()
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingID_makesOtherwiseIdenticalAssetsUnequal() {
        XCTAssertNotEqual(Self.makeAsset(), Self.makeAsset())
    }

    func test_embeddedMarkersAndBroadcastWaveMetadata_defaultToEmptyAndNil() {
        let asset = Self.makeAsset()
        XCTAssertTrue(asset.embeddedMarkers.isEmpty)
        XCTAssertNil(asset.broadcastWaveMetadata)
    }

    func test_fieldsArePreservedExactlyAsInitialized() {
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 12), label: "Marker 1")
        let bwf = BroadcastWaveMetadata(description: "Location mix", originator: "Field Recorder")
        let asset = Self.makeAsset(embeddedMarkers: [marker], broadcastWaveMetadata: bwf)

        XCTAssertEqual(asset.embeddedMarkers, [marker])
        XCTAssertEqual(asset.broadcastWaveMetadata, bwf)
    }

    /// Structural proof of SPEC.md §4.10's invariant: `AudioAsset` never
    /// holds raw or downsampled sample data. Enumerating `Mirror`'s children
    /// means this test fails the moment a future edit adds a stored property
    /// this list doesn't account for — not just an assertion that happens to
    /// pass today.
    func test_hasNoStoredPropertyCapableOfHoldingSampleData() {
        let mirror = Mirror(reflecting: Self.makeAsset())
        let propertyNames = Set(mirror.children.compactMap(\.label))

        XCTAssertEqual(
            propertyNames,
            [
                "id", "originalFileName", "securityScopedBookmark", "duration",
                "sampleRate", "channelCount", "bitDepth", "embeddedMarkers",
                "broadcastWaveMetadata", "importedAt",
            ]
        )
    }
}

final class EmbeddedMarkerTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = EmbeddedMarker(position: Timecode(offsetSeconds: 5), label: "Intro", note: "Fade up")
        XCTAssertEqual(original, original)
    }

    func test_labelAndNote_defaultToNilWhenOmitted() {
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 5))
        XCTAssertNil(marker.label)
        XCTAssertNil(marker.note)
    }
}

final class BroadcastWaveMetadataTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = BroadcastWaveMetadata(
            description: "Location mix",
            originator: "Field Recorder",
            originatorReference: "REF-1",
            originationDate: Date(timeIntervalSince1970: 0),
            timeReferenceSamples: 48000
        )
        XCTAssertEqual(original, original)
    }

    func test_allFields_defaultToNilWhenOmitted() {
        let bwf = BroadcastWaveMetadata()
        XCTAssertNil(bwf.description)
        XCTAssertNil(bwf.originator)
        XCTAssertNil(bwf.originatorReference)
        XCTAssertNil(bwf.originationDate)
        XCTAssertNil(bwf.timeReferenceSamples)
    }
}
