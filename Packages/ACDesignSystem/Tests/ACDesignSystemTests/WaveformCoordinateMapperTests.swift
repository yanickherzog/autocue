@testable import ACDesignSystem
import XCTest

/// `WaveformCoordinateMapper`'s pixel↔time math, independent of
/// `WaveformView`/`WaveformInteractionView` themselves — `ROADMAP.md`
/// D9/T9.3's own Testing Requirements name this pure-function coverage
/// explicitly.
final class WaveformCoordinateMapperTests: XCTestCase {
    func test_secondsAtPixel_zoomedIn_usesVisibleRangeNotFullFile() {
        let seconds = WaveformCoordinateMapper.secondsAtPixel(
            50,
            viewWidth: 100,
            visibleRangeSeconds: 100 ... 200
        )
        XCTAssertEqual(seconds, 150, accuracy: 0.0001)
    }

    func test_pixelAtSeconds_isTheInverseOfSecondsAtPixel() {
        let pixel = WaveformCoordinateMapper.pixelAtSeconds(150, viewWidth: 100, visibleRangeSeconds: 100 ... 200)
        XCTAssertEqual(pixel, 50, accuracy: 0.0001)
    }

    func test_draggingWhileZoomed_producesTheSameTimecodeAsDraggingUnzoomed() {
        // The specific correctness bar SPEC.md §4.15 calls out: dragging a
        // given physical boundary produces the same resulting offset
        // whether zoomed or not — a naive full-file mapping would silently
        // reposition by exactly the zoom factor's error.
        let unzoomedSeconds = WaveformCoordinateMapper.secondsAtPixel(
            250,
            viewWidth: 1000,
            visibleRangeSeconds: 0 ... 1000
        )
        // Zoomed into [200, 300] — pixel 250/1000 of a 100-wide window lands
        // at the same physical instant (250s) as above.
        let zoomedSeconds = WaveformCoordinateMapper.secondsAtPixel(
            500,
            viewWidth: 1000,
            visibleRangeSeconds: 200 ... 300
        )
        XCTAssertEqual(unzoomedSeconds, 250, accuracy: 0.0001)
        XCTAssertEqual(zoomedSeconds, 250, accuracy: 0.0001)
    }

    func test_panning_shiftsAtConstantWidth() {
        let result = WaveformCoordinateMapper.panning(100 ... 200, byDeltaSeconds: 10, fileDurationSeconds: 1000)
        XCTAssertEqual(result.lowerBound, 110, accuracy: 0.0001)
        XCTAssertEqual(result.upperBound, 210, accuracy: 0.0001)
        XCTAssertEqual(result.upperBound - result.lowerBound, 100, accuracy: 0.0001)
    }

    func test_panning_clampsAtTheStartOfTheFile() {
        let result = WaveformCoordinateMapper.panning(0 ... 100, byDeltaSeconds: -50, fileDurationSeconds: 1000)
        XCTAssertEqual(result.lowerBound, 0, accuracy: 0.0001)
        XCTAssertEqual(result.upperBound, 100, accuracy: 0.0001)
    }

    func test_panning_clampsAtTheEndOfTheFile() {
        let result = WaveformCoordinateMapper.panning(900 ... 1000, byDeltaSeconds: 500, fileDurationSeconds: 1000)
        XCTAssertEqual(result.lowerBound, 900, accuracy: 0.0001)
        XCTAssertEqual(result.upperBound, 1000, accuracy: 0.0001)
    }

    func test_zooming_narrowsAroundCenterPoint() {
        let result = WaveformCoordinateMapper.zooming(
            0 ... 100,
            by: 2,
            aroundSeconds: 50,
            fileDurationSeconds: 1000
        )
        XCTAssertEqual(result.upperBound - result.lowerBound, 50, accuracy: 0.0001)
        XCTAssertEqual(result.lowerBound, 25, accuracy: 0.0001)
        XCTAssertEqual(result.upperBound, 75, accuracy: 0.0001)
    }

    func test_zooming_neverExceedsFileDuration() {
        let result = WaveformCoordinateMapper.zooming(
            0 ... 100,
            by: 0.01,
            aroundSeconds: 50,
            fileDurationSeconds: 1000
        )
        XCTAssertLessThanOrEqual(result.upperBound - result.lowerBound, 1000)
    }
}
