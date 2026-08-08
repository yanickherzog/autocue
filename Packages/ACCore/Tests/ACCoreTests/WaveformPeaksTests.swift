@testable import ACCore
import XCTest

final class WaveformPeaksTests: XCTestCase {
    private static func makeBuckets(count: Int = 4096) -> [WaveformPeakBucket] {
        Array(repeating: WaveformPeakBucket(min: -0.5, max: 0.5), count: count)
    }

    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = WaveformPeaks(audioAssetID: UUID(), resolution: 4096, buckets: Self.makeBuckets())
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingID_makesOtherwiseIdenticalPeaksUnequal() {
        let audioAssetID = UUID()
        XCTAssertNotEqual(
            WaveformPeaks(audioAssetID: audioAssetID, resolution: 4096, buckets: Self.makeBuckets()),
            WaveformPeaks(audioAssetID: audioAssetID, resolution: 4096, buckets: Self.makeBuckets())
        )
    }

    func test_isHashable_forUseAsASetElement() {
        let peaks = WaveformPeaks(audioAssetID: UUID(), resolution: 4096, buckets: Self.makeBuckets())
        XCTAssertEqual(Set([peaks, peaks]).count, 1)
    }

    func test_bucketsLength_matchesResolution() {
        let peaks = WaveformPeaks(audioAssetID: UUID(), resolution: 4096, buckets: Self.makeBuckets())
        XCTAssertEqual(peaks.buckets.count, peaks.resolution)
    }

    /// SPEC.md §4.15's documented memory bound: 4096 buckets × 2 `Float` (8
    /// bytes) = 32,768 bytes.
    func test_fixedResolutionOverview_memoryFootprintMatchesDocumentedBound() {
        let peaks = WaveformPeaks(audioAssetID: UUID(), resolution: 4096, buckets: Self.makeBuckets())
        let footprint = peaks.buckets.count * MemoryLayout<WaveformPeakBucket>.stride
        XCTAssertEqual(footprint, 32768)
    }
}

final class WaveformPeakBucketTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let bucket = WaveformPeakBucket(min: -1, max: 1)
        XCTAssertEqual(bucket, bucket)
    }

    func test_isHashable_forUseAsASetElement() {
        XCTAssertEqual(Set([WaveformPeakBucket(min: -1, max: 1), WaveformPeakBucket(min: -1, max: 1)]).count, 1)
    }
}
