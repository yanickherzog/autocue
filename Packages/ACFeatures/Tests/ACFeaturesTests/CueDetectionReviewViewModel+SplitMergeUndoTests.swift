import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `splitRequested`/`mergeRequested`'s real `UndoManager` support
/// (`CueDetectionReviewViewModel+SplitMergeUndo.swift`), mirroring
/// `CueDetectionReviewViewModel+DeleteTests.swift`'s established pattern for
/// the same kind of test — split into its own file for the same reason that
/// file is separate from `CueDetectionReviewViewModelTests.swift`.
@MainActor
final class CueDetectionReviewSplitMergeUndoTests: XCTestCase {
    // MARK: - Split

    /// SPEC.md §4.19: "undo deletes the newly-created second Cue and
    /// restores the first Cue's pre-split startTimecode/duration."
    func test_splitRequested_undo_restoresOriginalSingleCue() async throws {
        let original = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let env = makeCueDetectionReviewEnvironment(cues: [original])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 25, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first?.id, original.id)
        XCTAssertEqual(restored?.cues.first?.startTimecode, original.startTimecode)
        XCTAssertEqual(restored?.cues.first?.duration, original.duration)
        loadTask.cancel()
    }

    /// Redo must re-apply the split, confirming the undo handler re-registers
    /// its own inverse rather than being a single-shot action — the same
    /// property `CueDetectionReviewViewModel+DeleteTests.swift` already
    /// proves for delete.
    func test_splitRequested_redo_splitsAgain() async throws {
        let original = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [original])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 25, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }

        undoManager.redo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(try XCTUnwrap(updated?.cues.first?.duration.seconds), 15, accuracy: 0.0001)
        loadTask.cancel()
    }

    /// An ineligible split (outside the cue's region) is a silent no-op per
    /// SPEC.md §4.15 — it must not leave a bogus undo action registered for
    /// a mutation that never happened.
    func test_splitRequested_ineligible_doesNotRegisterUndo() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.splitRequested(atSeconds: 5, undoManager: undoManager) // before the cue's own start
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(undoManager.canUndo)
        loadTask.cancel()
    }

    // MARK: - Merge

    /// SPEC.md §4.19's "Undo losslessness" requirement: a snapshot-based
    /// restore of both original `Cue` records exactly as they existed before
    /// the merge — not a computed reversal. Uses two cues with genuinely
    /// different title/notes/rightHolders so the forward merge actually
    /// combines/drops something real, proving undo brings it *all* back
    /// rather than just the fields a naive reversal would happen to recover.
    func test_mergeRequested_undo_restoresBothOriginalCuesLossy() async throws {
        let fixture = Self.makeLossyMergeFixture()
        let preceding = fixture.preceding
        let following = fixture.following
        let precedingRightHolder = fixture.precedingRightHolder
        let followingRightHolder = fixture.followingRightHolder
        let env = makeCueDetectionReviewEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.mergeRequested(markerID: 1, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            // The forward merge really did combine/drop data -- confirms
            // this test exercises the lossy path, not a no-op merge.
            return updated?.cues.count == 1
                && updated?.cues.first?.title == "Opening Theme" // following's title discarded
                && updated?.cues.first?.rightHolders.count == 2
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }
        let restored = try await projectRepository.fetch(id: project.id)
        let restoredPreceding = try XCTUnwrap(restored?.cues.first { $0.id == preceding.id })
        let restoredFollowing = try XCTUnwrap(restored?.cues.first { $0.id == following.id })

        XCTAssertEqual(restoredPreceding.title, "Opening Theme")
        XCTAssertEqual(restoredPreceding.notes, "preceding notes")
        XCTAssertEqual(restoredPreceding.rightHolders, [precedingRightHolder])
        XCTAssertEqual(restoredPreceding.duration, MediaDuration(seconds: 30))

        // The real losslessness claim: "Bridge"/its notes/its right-holder
        // were combined away by the forward merge and must come all the
        // way back, not just be inferred/dropped.
        XCTAssertEqual(restoredFollowing.title, "Bridge")
        XCTAssertEqual(restoredFollowing.notes, "following notes")
        XCTAssertEqual(restoredFollowing.rightHolders, [followingRightHolder])
        XCTAssertEqual(restoredFollowing.startTimecode, Timecode(offsetSeconds: 40))
        XCTAssertEqual(restoredFollowing.duration, MediaDuration(seconds: 20))

        // Original display order restored too, not just presence.
        XCTAssertEqual(restored?.cues.map(\.id), [preceding.id, following.id])
        loadTask.cancel()
    }

    func test_mergeRequested_redo_mergesAgain() async throws {
        let preceding = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let following = makeCueDetectionReviewCue(startSeconds: 40, duration: 20) // [40, 60)
        let env = makeCueDetectionReviewEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.mergeRequested(markerID: 1, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }

        undoManager.redo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(try XCTUnwrap(updated?.cues.first?.duration.seconds), 50, accuracy: 0.0001)
        loadTask.cancel()
    }

    /// An ineligible merge (no preceding neighbor) is a silent no-op per
    /// SPEC.md §4.15 — must not register a bogus undo either.
    func test_mergeRequested_ineligible_doesNotRegisterUndo() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.mergeRequested(markerID: 0, undoManager: undoManager) // no preceding neighbor
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(undoManager.canUndo)
        loadTask.cancel()
    }

    /// Two cues with genuinely different title/notes/rightHolders, so the
    /// forward merge in `test_mergeRequested_undo_restoresBothOriginalCuesLossy`
    /// actually combines/drops something real — extracted purely to keep
    /// that test under this project's function-body-length lint limit.
    private static func makeLossyMergeFixture() -> LossyMergeFixture {
        let precedingRightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer,
            performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let followingRightHolder = CueRightHolder(
            party: .person(UUID()), role: .author,
            performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let preceding = Cue(
            title: "Opening Theme",
            duration: MediaDuration(seconds: 30),
            rightHolders: [precedingRightHolder],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: 10),
            notes: "preceding notes"
        )
        let following = Cue(
            title: "Bridge",
            duration: MediaDuration(seconds: 20),
            rightHolders: [followingRightHolder],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: 40),
            notes: "following notes"
        )
        return LossyMergeFixture(
            preceding: preceding,
            precedingRightHolder: precedingRightHolder,
            following: following,
            followingRightHolder: followingRightHolder
        )
    }
}

private struct LossyMergeFixture {
    let preceding: Cue
    let precedingRightHolder: CueRightHolder
    let following: Cue
    let followingRightHolder: CueRightHolder
}
