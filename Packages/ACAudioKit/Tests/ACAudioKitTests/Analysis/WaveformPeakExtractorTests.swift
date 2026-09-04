@testable import ACAudioKit
import ACCore
import XCTest

final class WaveformPeakExtractorTests: XCTestCase {
    private var fixtureURLs: [URL] = []

    override func tearDown() {
        for url in fixtureURLs {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureURLs = []
        super.tearDown()
    }

    private func makeReader(channelSamples: [[Float]], sampleRate: Double = 48000) throws -> WAVStreamingReader {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        try WAVFixtureBuilder.writeWAVFile(sampleRate: sampleRate, channelSamples: channelSamples, to: url)
        fixtureURLs.append(url)
        return try WAVStreamingReader(url: url)
    }

    /// `resolution` is fixed regardless of file duration — SPEC.md §4.15's
    /// memory-bound invariant. Proved against two very differently sized
    /// files, not just one, so the bound is confirmed independent of
    /// duration rather than coincidentally true for one length.
    func test_alwaysProducesExactlyResolutionBuckets_regardlessOfFileDuration() throws {
        let shortReader = try makeReader(channelSamples: [[Float](repeating: 0.1, count: 1000)])
        let shortBuckets = try WaveformPeakExtractor.extract(reader: shortReader, resolution: 4096)
        XCTAssertEqual(shortBuckets.count, 4096)

        let longReader = try makeReader(channelSamples: [[Float](repeating: 0.1, count: 2_000_000)])
        let longBuckets = try WaveformPeakExtractor.extract(reader: longReader, resolution: 4096)
        XCTAssertEqual(longBuckets.count, 4096)
    }

    /// SPEC.md §4.15: 4096 buckets × 2 `Float` (8 bytes) = 32,768 bytes.
    func test_persistedOverview_memoryFootprintMatchesDocumentedBound() throws {
        let reader = try makeReader(channelSamples: [[Float](repeating: 0, count: 100_000)])
        let buckets = try WaveformPeakExtractor.extract(reader: reader, resolution: 4096)

        let footprint = buckets.count * MemoryLayout<WaveformPeakBucket>.stride
        XCTAssertEqual(buckets.count, 4096)
        XCTAssertLessThanOrEqual(footprint, 4096 * 8 + 64) // a little slack for struct padding, not the raw fields
    }

    func test_capturesKnownPeaks_perBucket() throws {
        // 4 buckets, 400 samples each (1600 total): bucket 2 (samples
        // 800..<1200) contains one clear positive peak, everything else flat
        // silence.
        var samples = [Float](repeating: 0, count: 1600)
        samples[900] = 0.75
        samples[950] = -0.5
        let reader = try makeReader(channelSamples: [samples])

        let buckets = try WaveformPeakExtractor.extract(reader: reader, resolution: 4)

        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(buckets[0].min, 0, accuracy: 0.001)
        XCTAssertEqual(buckets[0].max, 0, accuracy: 0.001)
        XCTAssertEqual(buckets[2].max, 0.75, accuracy: 0.01)
        XCTAssertEqual(buckets[2].min, -0.5, accuracy: 0.01)
        XCTAssertEqual(buckets[3].min, 0, accuracy: 0.001)
        XCTAssertEqual(buckets[3].max, 0, accuracy: 0.001)
    }

    func test_multiChannelSource_isMixedDownToMono_notJustFirstChannel() throws {
        // Left channel silent, right channel loud — a "first channel only"
        // bug would report this whole file as silent.
        let left = [Float](repeating: 0, count: 1000)
        let right = [Float](repeating: 0.8, count: 1000)
        let reader = try makeReader(channelSamples: [left, right])

        let buckets = try WaveformPeakExtractor.extract(reader: reader, resolution: 1)

        XCTAssertEqual(buckets[0].max, 0.4, accuracy: 0.01) // mixed down: (0 + 0.8) / 2
    }

    /// Exercises the "bucket spans many chunks" branch of the accumulator's
    /// overlap math directly, using a tiny chunk size relative to bucket
    /// width — the inverse of the "chunk spans many buckets" case every
    /// other test above already exercises by using the (much larger)
    /// default chunk size against a small file.
    func test_smallChunkSize_relativeToBucketWidth_stillAccumulatesCorrectly() throws {
        var samples = [Float](repeating: 0, count: 1000)
        samples[500] = 0.9
        let reader = try makeReader(channelSamples: [samples])

        let buckets = try WaveformPeakExtractor.extract(reader: reader, resolution: 2, chunkFrameCount: 10)

        XCTAssertEqual(buckets[1].max, 0.9, accuracy: 0.01)
        XCTAssertEqual(buckets[0].max, 0, accuracy: 0.001)
    }

    func test_boundedRange_onDemandDetail_reducesOnlyTheRequestedSubRange() throws {
        var samples = [Float](repeating: 0, count: 1000)
        samples[100] = 0.6 // inside the requested range
        samples[900] = 0.9 // outside the requested range
        let reader = try makeReader(channelSamples: [samples])

        let buckets = try WaveformPeakExtractor.extract(
            reader: reader,
            resolution: 2,
            startFrame: 0,
            endFrame: 200
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertTrue(buckets.contains { $0.max > 0.5 }) // the 0.6 peak was captured
        XCTAssertTrue(buckets.allSatisfy { $0.max < 0.8 }) // the out-of-range 0.9 peak was not
    }

    func test_reportsProgress_towardCompletion() throws {
        let reader = try makeReader(channelSamples: [[Float](repeating: 0.1, count: 100_000)])
        var lastProgress = 0.0
        _ = try WaveformPeakExtractor.extract(reader: reader, resolution: 4096, chunkFrameCount: 1000) { progress in
            lastProgress = progress
        }
        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.001)
    }
}
