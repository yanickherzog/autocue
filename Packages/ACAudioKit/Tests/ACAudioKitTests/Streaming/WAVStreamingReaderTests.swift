@testable import ACAudioKit
import AVFoundation
import XCTest

final class WAVStreamingReaderTests: XCTestCase {
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
        channelSamples: [[Float]]
    ) throws -> URL {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        try WAVFixtureBuilder.writeWAVFile(sampleRate: sampleRate, channelSamples: channelSamples, to: url)
        fixtureURLs.append(url)
        return url
    }

    func test_reportsCorrectMetadata_forAKnownFixture() throws {
        let sampleRate = 44100.0
        let frameCount = 4410 // exactly 0.1s
        let mono = [Float](repeating: 0.5, count: frameCount)
        let url = try makeFixture(sampleRate: sampleRate, channelSamples: [mono])

        let reader = try WAVStreamingReader(url: url)

        XCTAssertEqual(reader.sampleRate, sampleRate)
        XCTAssertEqual(reader.channelCount, 1)
        XCTAssertEqual(reader.totalFrameCount, AVAudioFramePosition(frameCount))
        XCTAssertEqual(reader.durationSeconds, 0.1, accuracy: 0.0001)
    }

    func test_reportsCorrectMetadata_forStereoFixture() throws {
        let frameCount = 1000
        let left = [Float](repeating: 0.25, count: frameCount)
        let right = [Float](repeating: -0.25, count: frameCount)
        let url = try makeFixture(channelSamples: [left, right])

        let reader = try WAVStreamingReader(url: url)

        XCTAssertEqual(reader.channelCount, 2)
        XCTAssertEqual(reader.totalFrameCount, AVAudioFramePosition(frameCount))
    }

    /// Proves this isn't loading the whole file into one buffer — multiple
    /// chunk callbacks must occur for a file larger than one chunk
    /// (`ROADMAP.md` D8 Acceptance Criteria).
    func test_multipleChunkCallbacks_occurForAFileLargerThanOneChunk() throws {
        let smallChunkSize: AVAudioFrameCount = 100
        let totalFrames = Int(smallChunkSize) * 3 + 17 // not an exact multiple, deliberately
        let mono = [Float](repeating: 0.1, count: totalFrames)
        let url = try makeFixture(channelSamples: [mono])

        let reader = try WAVStreamingReader(url: url)

        var chunkCount = 0
        var framesRead = 0
        while let buffer = try reader.readNextChunk(maxFrameCount: smallChunkSize) {
            chunkCount += 1
            framesRead += Int(buffer.frameLength)
            XCTAssertLessThanOrEqual(buffer.frameLength, smallChunkSize)
        }

        XCTAssertGreaterThan(chunkCount, 1)
        XCTAssertEqual(framesRead, totalFrames)
    }

    func test_readNextChunk_returnsNil_onceEndOfFileReached() throws {
        let url = try makeFixture(channelSamples: [[Float](repeating: 0, count: 10)])
        let reader = try WAVStreamingReader(url: url)

        _ = try reader.readNextChunk(maxFrameCount: 1000)
        XCTAssertNil(try reader.readNextChunk(maxFrameCount: 1000))
    }

    func test_seek_repositionsSubsequentReads() throws {
        var samples = [Float](repeating: 0, count: 100)
        for index in 50 ..< 100 {
            samples[index] = 1.0
        }
        let url = try makeFixture(channelSamples: [samples])
        let reader = try WAVStreamingReader(url: url)

        reader.seek(toFrame: 50)
        let buffer = try reader.readNextChunk(maxFrameCount: 50)

        XCTAssertEqual(buffer?.frameLength, 50)
        let firstSample = buffer?.floatChannelData?[0][0]
        XCTAssertEqual(Double(firstSample ?? 0), 1.0, accuracy: 0.01)
    }

    func test_bitDepth_reportsSourceFormat_not16BitFloatProcessingFormat() throws {
        // WAVFixtureBuilder always writes 16-bit PCM — this proves bitDepth
        // comes from the source `fileFormat`, not the Float32
        // `processingFormat` every chunk is actually decoded into.
        let url = try makeFixture(channelSamples: [[Float](repeating: 0, count: 10)])
        let reader = try WAVStreamingReader(url: url)

        XCTAssertEqual(reader.bitDepth, 16)
    }
}
