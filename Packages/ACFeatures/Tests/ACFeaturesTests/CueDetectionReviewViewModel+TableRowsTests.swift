import ACCore
import ACDesignSystem
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// SPEC.md §4.3's corrected TC In/TC Out rule (2026-09-10): displayed
/// timecodes are the film's own absolute timecode — `Setup.timecodeStart`'s
/// offset added to a cue's audio-file-relative `Cue.startTimecode` — not
/// `Cue.startTimecode` alone. `Cue.startTimecode` itself must stay untouched
/// (`CueDetectionReviewViewModelTests`' drag/split/merge tests already cover
/// that it stays audio-file-relative); these tests cover only the display
/// layer this fix actually changed.
@MainActor
final class CueDetectionReviewTableRowsTests: XCTestCase {
    func test_tableRows_addsSetupTimecodeStart_toBothTCInAndTCOut() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40) audio-file-relative
        let env = makeCueDetectionReviewEnvironment(
            cues: [cue],
            timecodeStart: Timecode(offsetSeconds: 3600) // 01:00:00:00
        )
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        loadTask.cancel()

        let row = try XCTUnwrap(viewModel.tableRows.first)
        XCTAssertEqual(row.tcIn, "01:00:10:00")
        XCTAssertEqual(row.tcOut, "01:00:40:00")
    }

    func test_tableRows_nilTimecodeStart_treatsAsZeroOffset() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue], timecodeStart: nil)
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        loadTask.cancel()

        let row = try XCTUnwrap(viewModel.tableRows.first)
        XCTAssertEqual(row.tcIn, "00:00:10:00")
        XCTAssertEqual(row.tcOut, "00:00:40:00")
    }

    func test_tableRows_cueWithNoStartTimecode_stillShowsPlaceholder_regardlessOfTimecodeStart() async throws {
        let cueWithoutPosition = Cue(title: "Manual", duration: .zero, rightHolders: [], source: .manual)
        let env = makeCueDetectionReviewEnvironment(
            cues: [cueWithoutPosition],
            timecodeStart: Timecode(offsetSeconds: 3600)
        )
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        loadTask.cancel()

        let row = try XCTUnwrap(viewModel.tableRows.first)
        XCTAssertEqual(row.tcIn, "—")
        XCTAssertEqual(row.tcOut, "—")
    }

    func test_tableRows_length_isUnaffectedByTimecodeStart() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(
            cues: [cue],
            timecodeStart: Timecode(offsetSeconds: 3600)
        )
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        loadTask.cancel()

        let row = try XCTUnwrap(viewModel.tableRows.first)
        XCTAssertEqual(row.length, "00:30")
    }

    /// Marker/waveform/playback positions must stay audio-file-relative even
    /// though the same cue's TC In/TC Out display is film-absolute — the two
    /// must not be conflated in the same rendering pass.
    func test_markers_stayAudioFileRelative_whileTableRowsAreFilmAbsolute() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(
            cues: [cue],
            timecodeStart: Timecode(offsetSeconds: 3600)
        )
        let viewModel = env.viewModel

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }
        loadTask.cancel()

        XCTAssertEqual(viewModel.markers.first?.offsetSeconds, 10)
        XCTAssertEqual(viewModel.tableRows.first?.tcIn, "01:00:10:00")
    }
}
