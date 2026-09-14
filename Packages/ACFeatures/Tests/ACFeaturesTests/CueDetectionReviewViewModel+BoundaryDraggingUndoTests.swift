import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `boundaryDragged`'s real `UndoManager` support
/// (`CueDetectionReviewViewModel+BoundaryDragging.swift`), mirroring
/// `CueDetectionReviewViewModel+SplitMergeUndoTests.swift`'s established
/// pattern for the same kind of test — split into its own file for the same
/// reason that file is separate from `CueDetectionReviewViewModelTests.swift`.
///
/// Unlike split/merge, boundary dragging has no real "ineligible" gate — any
/// live marker always resolves to a real cue ID already present in the
/// ViewModel's own `cues` snapshot, so there's no analogous
/// "doesNotRegisterUndo" case to test here.
@MainActor
final class CueDetectionReviewBoundaryDragUndoTests: XCTestCase {
    /// The independent (non-contiguous) branch — undo must restore the
    /// dragged cue's exact pre-drag `startTimecode`/`duration`, and must
    /// never touch the untouched neighbor across a real gap.
    func test_boundaryDragged_undo_restoresIndependentMarkerToOriginalPosition() async throws {
        let preceding = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let following = makeCueDetectionReviewCue(startSeconds: 50, duration: 20) // [50, 70), real gap
        let env = makeCueDetectionReviewEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.boundaryDragged(marker: .end(cueIndex: 0), toSeconds: 35, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 25
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 30
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first?.startTimecode, Timecode(offsetSeconds: 10))
        XCTAssertEqual(restored?.cues.first?.duration, MediaDuration(seconds: 30))
        // Known, deliberate exception (SPEC.md §4.19, same as merge's own
        // undo): `edit` always reclassifies to `.manual`, so the pre-drag
        // `.detectedFromAudio` source doesn't come back exactly.
        XCTAssertEqual(restored?.cues.first?.source, .manual)
        // The real gap-separated neighbor is never touched by either direction.
        XCTAssertEqual(restored?.cues.last?.startTimecode, Timecode(offsetSeconds: 50))
        XCTAssertEqual(restored?.cues.last?.duration, MediaDuration(seconds: 20))
        loadTask.cancel()
    }

    /// The atomic contiguous push-through branch — undo must restore BOTH
    /// affected cues to their exact pre-drag boundaries, matching how the
    /// forward drag itself moves them atomically.
    func test_boundaryDragged_undo_restoresBothCuesInContiguousPushThrough() async throws {
        let preceding = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let following = makeCueDetectionReviewCue(startSeconds: 40, duration: 20) // [40, 60), touching
        let env = makeCueDetectionReviewEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.boundaryDragged(marker: .end(cueIndex: 0), toSeconds: 45, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 35
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 30
                && (try? XCTUnwrap(updated?.cues.last?.duration.seconds)) == 20
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first?.startTimecode, Timecode(offsetSeconds: 10))
        XCTAssertEqual(restored?.cues.first?.duration, MediaDuration(seconds: 30))
        XCTAssertEqual(restored?.cues.last?.startTimecode, Timecode(offsetSeconds: 40))
        XCTAssertEqual(restored?.cues.last?.duration, MediaDuration(seconds: 20))
        loadTask.cancel()
    }

    /// A third, uninvolved cue must never be touched by an undo of a
    /// push-through that only involves its two immediate neighbors.
    func test_boundaryDragged_pushThroughUndo_doesNotAffectAThirdUninvolvedCue() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let second = makeCueDetectionReviewCue(startSeconds: 40, duration: 20) // [40, 60), touching first
        let third = makeCueDetectionReviewCue(startSeconds: 80, duration: 10) // [80, 90), far away
        let env = makeCueDetectionReviewEnvironment(cues: [first, second, third])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 3 }

        viewModel.boundaryDragged(marker: .end(cueIndex: 0), toSeconds: 45, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 35
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 30
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues[2].startTimecode, Timecode(offsetSeconds: 80))
        XCTAssertEqual(restored?.cues[2].duration, MediaDuration(seconds: 10))
        loadTask.cancel()
    }

    /// Redo must re-apply the atomic push-through, confirming the undo
    /// handler re-registers its own inverse rather than being a single-shot
    /// action — the same property already proven for delete/split/merge.
    func test_boundaryDragged_redo_movesBoundaryAgainAtomically() async throws {
        let preceding = makeCueDetectionReviewCue(startSeconds: 10, duration: 30) // [10, 40)
        let following = makeCueDetectionReviewCue(startSeconds: 40, duration: 20) // [40, 60), touching
        let env = makeCueDetectionReviewEnvironment(cues: [preceding, following])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.boundaryDragged(marker: .end(cueIndex: 0), toSeconds: 45, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 35
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 30
        }

        undoManager.redo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return try XCTUnwrap(updated?.cues.first?.duration.seconds) == 35
        }
        let redone = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(redone?.cues.last?.startTimecode, Timecode(offsetSeconds: 45))
        XCTAssertEqual(redone?.cues.last?.duration, MediaDuration(seconds: 15))
        loadTask.cancel()
    }
}
