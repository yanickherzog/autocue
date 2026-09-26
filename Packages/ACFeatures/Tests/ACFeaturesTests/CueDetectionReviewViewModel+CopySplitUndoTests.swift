import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `copySplitToOtherCuesRequested`/undo-redo
/// (`CueDetectionReviewViewModel+CopySplitUndo.swift`, `ROADMAP.md` D10) —
/// split into its own test file mirroring the production split, same
/// reason `+DeleteTests.swift`/`+SplitMergeUndoTests.swift` already are.
@MainActor
final class CueDetectionReviewCopySplitUndoTests: XCTestCase {
    func test_copySplitToOtherCues_writesTheSourcesSplitOntoEveryOtherCue() async throws {
        let sourceRightHolders = [
            CueRightHolder(
                party: .person(Person.ID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
            ),
        ]
        let source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let other1 = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let other2 = makeCueDetectionReviewCue(startSeconds: 90, duration: 15)
        let env = makeCueDetectionReviewEnvironment(cues: [source, other1, other2])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 3 }

        viewModel.copySplitToOtherCuesRequested(rightHolders: sourceRightHolders, undoManager: nil)

        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.allSatisfy { $0.rightHolders == sourceRightHolders } == true
        }
        loadTask.cancel()
    }

    /// The exact scenario requested: copy split to all cues, then ⌘Z,
    /// confirming every cue's original right-holder data is fully restored —
    /// not partially, and via a single undo action, not one per cue.
    func test_copySplitToOtherCues_undo_fullyRestoresEveryAffectedCuesOriginalData() async throws {
        let sourceRightHolders = [
            CueRightHolder(
                party: .person(Person.ID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
            ),
        ]
        let originalOther1 = [
            CueRightHolder(
                party: .person(Person.ID()), role: .composer, performanceBroadcastShare: 50, mechanicalRightsShare: 50
            ),
            CueRightHolder(
                party: .person(Person.ID()), role: .author, performanceBroadcastShare: 50, mechanicalRightsShare: 50
            ),
        ]
        let originalOther2: [CueRightHolder] = []

        var source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        source = Cue(
            id: source.id, title: source.title, duration: source.duration, rightHolders: sourceRightHolders,
            source: source.source, startTimecode: source.startTimecode
        )
        var other1 = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        other1 = Cue(
            id: other1.id, title: other1.title, duration: other1.duration, rightHolders: originalOther1,
            source: other1.source, startTimecode: other1.startTimecode
        )
        let other2 = makeCueDetectionReviewCue(startSeconds: 90, duration: 15)

        let env = makeCueDetectionReviewEnvironment(cues: [source, other1, other2])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 3 }

        viewModel.copySplitToOtherCuesRequested(rightHolders: sourceRightHolders, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.allSatisfy { $0.rightHolders == sourceRightHolders } == true
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other1.id }?.rightHolders == originalOther1
        }

        let restored = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first { $0.id == source.id }?.rightHolders, sourceRightHolders)
        XCTAssertEqual(restored?.cues.first { $0.id == other1.id }?.rightHolders, originalOther1)
        XCTAssertEqual(restored?.cues.first { $0.id == other2.id }?.rightHolders, originalOther2)
        loadTask.cancel()
    }

    /// Redo (⌘⇧Z) must re-apply the copy to every cue again — confirming the
    /// undo handler re-registers its own inverse rather than being a
    /// single-shot action, the same "alternate correctly" requirement
    /// `+DeleteTests.swift`/`+SplitMergeUndoTests.swift` already cover for
    /// their own structural mutations.
    func test_copySplitToOtherCues_redo_reappliesTheCopyToEveryCue() async throws {
        let sourceRightHolders = [
            CueRightHolder(
                party: .person(Person.ID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
            ),
        ]
        let source = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let other = makeCueDetectionReviewCue(startSeconds: 50, duration: 20)
        let env = makeCueDetectionReviewEnvironment(cues: [source, other])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project
        let undoManager = UndoManager()

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 2 }

        viewModel.copySplitToOtherCuesRequested(rightHolders: sourceRightHolders, undoManager: undoManager)
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.rightHolders == sourceRightHolders
        }

        undoManager.undo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.rightHolders.isEmpty == true
        }

        undoManager.redo()
        try await waitUntilCueDetectionReviewConditionMet {
            let updated = try await projectRepository.fetch(id: project.id)
            return updated?.cues.first { $0.id == other.id }?.rightHolders == sourceRightHolders
        }
        loadTask.cancel()
    }
}
