import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `titleChanged`/`startTimecodeChanged` (`CueDetectionReviewViewModel
/// +RowDetail.swift`, `ROADMAP.md` D10/T10.2) — split into its own file
/// mirroring the production split.
@MainActor
final class CueDetectionReviewRowDetailTests: XCTestCase {
    // MARK: - Title

    func test_titleChanged_savesAfterTheDebounceDelay() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.titleChanged(cueID: cue.id, newTitle: "Opening Theme")

        // Confirms debounced, not immediate -- matching SPEC.md §4.18's
        // split between structural mutations (immediate) and continuous
        // field-level edits (debounced), the same distinction
        // `SetupViewModelTests.test_updateDebounced_savesAfterTheDelay_notImmediately`
        // already proves for `Setup` field edits.
        let immediatelyAfter = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(immediatelyAfter?.cues.first?.title, "")

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.title == "Opening Theme"
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first?.source, .manual)
        loadTask.cancel()
    }

    /// Editing one cue's title never cancels another's still-pending save --
    /// each is debounced against its own `Cue.ID`, not one shared task.
    func test_titleChanged_onTwoDifferentCues_bothEventuallySave() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let second = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [first, second])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.titleChanged(cueID: first.id, newTitle: "First")
        viewModel.titleChanged(cueID: second.id, newTitle: "Second")

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.title == "First" && updated?.cues.last?.title == "Second"
        }
        loadTask.cancel()
    }

    // MARK: - Direct timecode edit

    func test_startTimecodeChanged_savesAfterTheDebounceDelay() async throws {
        let cue = Cue(title: "Manual", duration: MediaDuration(seconds: 10), rightHolders: [], source: .manual)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.startTimecodeChanged(cueID: cue.id, newTimecode: Timecode(offsetSeconds: 42))

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.startTimecode == Timecode(offsetSeconds: 42)
        }
        loadTask.cancel()
    }
}
