import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `copyRecordingLabelToOtherCuesRequested`/undo-redo
/// (`CueDetectionReviewViewModel+CopyLabelUndo.swift`, SPEC.md §4.26) —
/// split into its own test file mirroring the production split, same
/// reason `+CopySplitUndoTests.swift`/`+SplitMergeUndoTests.swift` already
/// are.
@MainActor
final class CueDetectionReviewCopyLabelUndoTests: XCTestCase {
    func test_copyLabel_writesTheSourcesLabelAndLabelNumberOntoEveryOtherCue() async throws {
        let labelID = UUID()
        let source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let other1 = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let other2 = makeCueDetectionReviewCue(startSeconds: 90, duration: 15)
        let env = makeCueDetectionReviewEnvironment(cues: [source, other1, other2])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 3 }

        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: .label(labelID),
            recordingLabelNumber: "NDR-4471",
            undoManager: nil
        )

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.allSatisfy {
                $0.recordingLabel == .label(labelID) && $0.recordingLabelNumber == "NDR-4471"
            } == true
        }
        loadTask.cancel()
    }

    /// The ISRC-Nr. explicitly never copies — it identifies one specific
    /// master recording, a fact about that one cue's own usage, not
    /// something that makes sense to propagate just because two cues share
    /// a record label (SPEC.md §4.26).
    func test_copyLabel_neverCopiesTheISRC() async throws {
        let labelID = UUID()
        var source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        source = Cue(
            id: source.id,
            title: source.title,
            duration: source.duration,
            rightHolders: source.rightHolders,
            source: source.source,
            startTimecode: source.startTimecode,
            recordingLabel: .label(labelID),
            recordingLabelNumber: "NDR-4471",
            recordingISRC: "CH-A12-26-00001"
        )
        var other = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        other = Cue(
            id: other.id,
            title: other.title,
            duration: other.duration,
            rightHolders: other.rightHolders,
            source: other.source,
            startTimecode: other.startTimecode,
            recordingISRC: "CH-B99-26-00042"
        )
        let env = makeCueDetectionReviewEnvironment(cues: [source, other])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: .label(labelID),
            recordingLabelNumber: "NDR-4471",
            undoManager: nil
        )

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.recordingLabel == .label(labelID)
        }

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first { $0.id == other.id }?.recordingISRC, "CH-B99-26-00042")
        XCTAssertEqual(updated?.cues.first { $0.id == source.id }?.recordingISRC, "CH-A12-26-00001")
        loadTask.cancel()
    }

    /// **Regression coverage for the exact bug class found this round:** a
    /// previous bulk-mutation path dropped recording-info fields at eight
    /// `Cue`-reconstruction sites. This asserts every *other* field on every
    /// affected cue — title, timecodes, right-holders, shares, ISRC,
    /// source — survives a label copy untouched, not just that the label
    /// fields themselves changed.
    func test_copyLabel_leavesEveryOtherFieldOnEveryAffectedCueUntouched() async throws {
        let labelID = UUID()
        let rightHolder = CueRightHolder(
            party: .person(Person.ID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let sourceBase = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let source = Cue(
            id: sourceBase.id, title: sourceBase.title, duration: sourceBase.duration, rightHolders: [],
            source: sourceBase.source, startTimecode: sourceBase.startTimecode,
            recordingLabel: .label(labelID), recordingLabelNumber: "NDR-4471"
        )
        let otherBase = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let other = Cue(
            id: otherBase.id, title: "Original Title", workNumber: "W-77", duration: otherBase.duration,
            rightHolders: [rightHolder], source: otherBase.source, startTimecode: otherBase.startTimecode,
            notes: "keep me", recordingISRC: "CH-B99-26-00042"
        )
        let env = makeCueDetectionReviewEnvironment(cues: [source, other])
        let (viewModel, projectRepository, project) = (env.viewModel, env.projectRepository, env.project)

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: .label(labelID), recordingLabelNumber: "NDR-4471", undoManager: nil
        )

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.recordingLabel == .label(labelID)
        }

        let updated = try await projectRepository.fetch(id: project.id)
        let updatedOther = try XCTUnwrap(updated?.cues.first { $0.id == other.id })
        XCTAssertEqual(updatedOther.title, "Original Title")
        XCTAssertEqual(updatedOther.workNumber, "W-77")
        XCTAssertEqual(updatedOther.startTimecode, other.startTimecode)
        XCTAssertEqual(updatedOther.duration, other.duration)
        XCTAssertEqual(updatedOther.rightHolders, [rightHolder])
        XCTAssertEqual(updatedOther.notes, "keep me")
        XCTAssertEqual(updatedOther.recordingISRC, "CH-B99-26-00042")
        XCTAssertEqual(updatedOther.recordingLabelNumber, "NDR-4471")
        loadTask.cancel()
    }

    /// A single-cue project has no "other cues" to copy onto — the write
    /// still succeeds (it's harmless/correct for it to re-write the source
    /// cue's own label onto itself), nothing throws, nothing hangs.
    func test_copyLabel_singleCueProject_copiesToNothingWithoutError() async throws {
        let labelID = UUID()
        let source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [source])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: .label(labelID),
            recordingLabelNumber: "NDR-4471",
            undoManager: nil
        )

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.recordingLabel == .label(labelID)
        }
        XCTAssertNil(viewModel.errorMessage)
        loadTask.cancel()
    }

    /// The exact scenario requested: copy label to all cues, then ⌘Z,
    /// confirming every cue's original label/label-number is fully restored
    /// — via a single undo action, not one per cue.
    func test_copyLabel_undo_fullyRestoresEveryAffectedCuesOriginalLabel() async throws {
        let sourceLabelID = UUID()
        let otherLabelID = UUID()

        let sourceBase = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let source = Cue(
            id: sourceBase.id, title: sourceBase.title, duration: sourceBase.duration, rightHolders: [],
            source: sourceBase.source, startTimecode: sourceBase.startTimecode,
            recordingLabel: .label(sourceLabelID), recordingLabelNumber: "NDR-4471"
        )
        let other1Base = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let other1 = Cue(
            id: other1Base.id, title: other1Base.title, duration: other1Base.duration, rightHolders: [],
            source: other1Base.source, startTimecode: other1Base.startTimecode,
            recordingLabel: .label(otherLabelID), recordingLabelNumber: "XYZ-1"
        )
        let other2 = makeCueDetectionReviewCue(startSeconds: 90, duration: 15)

        let env = makeCueDetectionReviewEnvironment(cues: [source, other1, other2])
        let (viewModel, projectRepository, project) = (env.viewModel, env.projectRepository, env.project)
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 3 }

        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: .label(sourceLabelID), recordingLabelNumber: "NDR-4471", undoManager: undoManager
        )
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.allSatisfy { $0.recordingLabel == .label(sourceLabelID) } == true
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other1.id }?.recordingLabel == .label(otherLabelID)
        }

        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first { $0.id == source.id }?.recordingLabel, .label(sourceLabelID))
        XCTAssertEqual(restored?.cues.first { $0.id == other1.id }?.recordingLabel, .label(otherLabelID))
        XCTAssertEqual(restored?.cues.first { $0.id == other1.id }?.recordingLabelNumber, "XYZ-1")
        XCTAssertNil(restored?.cues.first { $0.id == other2.id }?.recordingLabel)
        loadTask.cancel()
    }

    /// Redo (⌘⇧Z) must re-apply the copy to every cue again — confirming
    /// the undo handler re-registers its own inverse rather than being a
    /// single-shot action.
    func test_copyLabel_redo_reappliesTheCopyToEveryCue() async throws {
        let labelID = UUID()
        let source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let other = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [source, other])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: .label(labelID),
            recordingLabelNumber: "NDR-4471",
            undoManager: undoManager
        )
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.recordingLabel == .label(labelID)
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.recordingLabel == nil
        }

        undoManager.redo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.recordingLabel == .label(labelID)
        }
        loadTask.cancel()
    }
}
