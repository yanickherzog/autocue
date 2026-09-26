import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `addCue`/`moveCue` (`CueDetectionReviewViewModel+AddReorder.swift`,
/// `ROADMAP.md` D10/T10.1) — split into its own file mirroring the
/// production split, same reason `+DeleteTests.swift`/
/// `+SplitMergeUndoTests.swift` already are.
@MainActor
final class CueDetectionReviewAddReorderTests: XCTestCase {
    // MARK: - Add

    func test_addCue_appendsAFreshManualCue() async throws {
        let existing = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [existing])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.addCue(undoManager: nil)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }
        let updated = try await projectRepository.fetch(id: project.id)
        let added = try XCTUnwrap(updated?.cues.last)
        XCTAssertEqual(added.title, "")
        XCTAssertEqual(added.duration, .zero)
        XCTAssertNil(added.startTimecode)
        XCTAssertEqual(added.source, .manual)
        loadTask.cancel()
    }

    /// ⌘Z after "+ Add Cue" removes exactly the cue it created — captured
    /// from the *live* snapshot at undo time, not the blank values it was
    /// created with, since the user may have already edited it.
    func test_addCue_undo_removesTheAddedCue() async throws {
        let existing = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [existing])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.addCue(undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first?.id, existing.id)
        loadTask.cancel()
    }

    /// Redo (⌘⇧Z) restores the exact cue that was added — including a title
    /// typed into it *after* it was created but *before* undo, proving the
    /// inverse action captures the live snapshot at undo time, not the
    /// original blank creation values.
    func test_addCue_redo_restoresTheEditedTitle() async throws {
        let env = makeCueDetectionReviewEnvironment(cues: [])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.isEmpty }

        viewModel.addCue(undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        let afterAdd = try await projectRepository.fetch(id: project.id)
        let addedID = try XCTUnwrap(afterAdd?.cues.first?.id)

        viewModel.titleChanged(cueID: addedID, newTitle: "New Theme")
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.title == "New Theme"
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.isEmpty == true
        }

        undoManager.redo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first?.title, "New Theme")
        loadTask.cancel()
    }

    // MARK: - Reorder

    func test_moveCue_up_movesToPrecedingPosition() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let second = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [first, second])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.moveCue(at: 1, direction: .up, undoManager: nil)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.id == second.id
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [second.id, first.id])
        // No field on the moved cue changed -- in particular, source stays whatever it was.
        XCTAssertEqual(updated?.cues.first, second)
        loadTask.cancel()
    }

    func test_moveCue_atFirstRow_up_isANoOp() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let second = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [first, second])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.moveCue(at: 0, direction: .up, undoManager: nil)

        try await Task.sleep(nanoseconds: 50_000_000)
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [first.id, second.id])
        loadTask.cancel()
    }

    /// ⌘Z after a reorder moves the cue back to its original position — a
    /// plain reverse move, not a snapshot restore, since reorder never
    /// touches any `Cue` field.
    func test_moveCue_undo_movesBackToOriginalPosition() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let second = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let third = makeCueDetectionReviewCue(startSeconds: 90, duration: 15)
        let env = makeCueDetectionReviewEnvironment(cues: [first, second, third])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 3 }

        viewModel.moveCue(at: 0, direction: .down, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.id == second.id
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first?.id == first.id
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.map(\.id), [first.id, second.id, third.id])
        loadTask.cancel()
    }
}
