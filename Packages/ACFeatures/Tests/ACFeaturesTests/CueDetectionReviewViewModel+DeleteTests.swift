import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `deleteCue`/undo-redo (`CueDetectionReviewViewModel+Delete.swift`), split
/// into its own test file mirroring the production split, same reason
/// `CueDetectionReviewViewModelTests.swift`'s other structural mutations
/// (split/merge) already have their own `// MARK:` sections in one file —
/// this one adds real `UndoManager` interaction, different enough in kind
/// to warrant its own file rather than growing that one further.
@MainActor
final class CueDetectionReviewViewModelDeleteTests: XCTestCase {
    func test_deleteCue_writesThroughAndRemovesFromLiveCues() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let second = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [first, second])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.deleteCue(at: 0, undoManager: nil)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 1
        }
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first?.id, second.id)
        loadTask.cancel()
    }

    func test_deleteCue_outOfRangeIndex_isANoOp() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.deleteCue(at: 5, undoManager: nil)

        try await Task.sleep(nanoseconds: 50_000_000)
        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.count, 1)
        loadTask.cancel()
    }

    /// The real behavior SPEC.md §4.18 requires: ⌘Z immediately after a
    /// delete restores the cue, at its original position, with its full
    /// original field values.
    func test_deleteCue_undo_reinsertsExactCueAtOriginalIndex() async throws {
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

        viewModel.deleteCue(at: 1, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 2
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.count == 3
        }
        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(restored?.cues[1].startTimecode, second.startTimecode)
        XCTAssertEqual(restored?.cues[1].duration, second.duration)
        loadTask.cancel()
    }

    /// Redo (⌘⇧Z) must delete it again — confirming the undo handler
    /// re-registers its own inverse rather than being a single-shot action.
    func test_deleteCue_redo_deletesAgain() async throws {
        let first = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let second = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [first, second])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.deleteCue(at: 0, undoManager: undoManager)
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
        XCTAssertEqual(updated?.cues.first?.id, second.id)
        loadTask.cancel()
    }

    func test_deleteCue_noUndoManager_stillDeletes() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        viewModel.deleteCue(at: 0, undoManager: nil)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.isEmpty == true
        }
        loadTask.cancel()
    }
}
