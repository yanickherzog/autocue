import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `recordingLabelSelected`/`.recordingLabelCleared`/`.recordingLabelNumberChanged`/
/// `.recordingISRCChanged` (`CueDetectionReviewViewModel+RecordingInfo.swift`,
/// SPEC.md §4.26) — split into its own file mirroring the production split,
/// same pattern `CueDetectionReviewViewModel+RowDetailTests.swift` already
/// establishes for the sibling title/timecode edits.
@MainActor
final class CueDetectionReviewRecordingInfoTests: XCTestCase {
    // MARK: - Label (immediate)

    func test_recordingLabelSelected_savesImmediately_notDebounced() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let labelID = UUID()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        await viewModel.recordingLabelSelected(cueID: cue.id, party: .label(labelID))

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first?.recordingLabel, .label(labelID))
        XCTAssertEqual(updated?.cues.first?.source, .manual)
        loadTask.cancel()
    }

    func test_recordingLabelCleared_removesAnExistingLabel() async throws {
        let labelID = UUID()
        var cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .manual)
        cue = Cue(
            id: cue.id,
            title: cue.title,
            duration: cue.duration,
            rightHolders: cue.rightHolders,
            source: cue.source,
            startTimecode: cue.startTimecode,
            recordingLabel: .label(labelID)
        )
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        await viewModel.recordingLabelCleared(cueID: cue.id)

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertNil(updated?.cues.first?.recordingLabel)
        loadTask.cancel()
    }

    // MARK: - Label-Nr. (debounced)

    func test_recordingLabelNumberChanged_savesAfterTheDebounceDelay() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.recordingLabelNumberChanged(cueID: cue.id, newValue: "NDR-4471")

        let immediatelyAfter = try await projectRepository.fetch(id: project.id)
        XCTAssertNil(immediatelyAfter?.cues.first?.recordingLabelNumber)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.recordingLabelNumber == "NDR-4471"
        }
        loadTask.cancel()
    }

    // MARK: - ISRC-Nr. (debounced)

    func test_recordingISRCChanged_savesAfterTheDebounceDelay() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.recordingISRCChanged(cueID: cue.id, newValue: "CH-A12-26-00001")

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.recordingISRC == "CH-A12-26-00001"
        }
        loadTask.cancel()
    }

    func test_recordingISRCChanged_emptyString_savesAsNil() async throws {
        let labelID = UUID()
        var cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .manual)
        cue = Cue(
            id: cue.id,
            title: cue.title,
            duration: cue.duration,
            rightHolders: cue.rightHolders,
            source: cue.source,
            startTimecode: cue.startTimecode,
            recordingLabel: .label(labelID),
            recordingISRC: "CH-A12-26-00001"
        )
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.recordingISRCChanged(cueID: cue.id, newValue: "  ")

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.recordingISRC == nil
        }
        loadTask.cancel()
    }
}
