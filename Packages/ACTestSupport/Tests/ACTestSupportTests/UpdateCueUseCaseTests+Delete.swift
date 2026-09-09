import ACCore
@testable import ACTestSupport
import XCTest

/// `delete`/`insertForUndo` (`UpdateCueUseCase`'s D10/T10.1 pull-forward,
/// same as `edit`/`split`/`merge` in the primary file) — split into its own
/// file/extension purely to keep `UpdateCueUseCaseTests` under this
/// project's type-body-length lint limit, the same reason
/// `UpdateCueUseCaseMoveBoundaryTests+EdgeCases.swift` already is. Reuses
/// that class's `makeProject`/`makeCue` helpers, made non-`private` there
/// specifically so this file can share them.
extension UpdateCueUseCaseTests {
    // MARK: - Delete

    func test_delete_removesExactlyThatCue_leavesOthersUntouched() async throws {
        let first = Self.makeCue(title: "First", startSeconds: 10)
        let second = Self.makeCue(title: "Second", startSeconds: 50)
        let third = Self.makeCue(title: "Third", startSeconds: 90)
        let project = Self.makeProject(cues: [first, second, third])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        try await useCase.delete(projectID: project.id, cueID: second.id)

        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [first.id, third.id])
    }

    func test_delete_recomputesTotalMusicRuntime() async throws {
        let first = Self.makeCue(duration: 30, startSeconds: 10)
        let second = Self.makeCue(duration: 45, startSeconds: 50)
        let project = Self.makeProject(cues: [first, second])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        try await useCase.delete(projectID: project.id, cueID: second.id)

        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.setup.totalMusicRuntime, MediaDuration(seconds: 30))
    }

    func test_delete_unknownCueID_throwsCueNotFound() async throws {
        let project = Self.makeProject(cues: [])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)
        let unknownID = UUID()

        do {
            try await useCase.delete(projectID: project.id, cueID: unknownID)
            XCTFail("Expected cueNotFound")
        } catch UpdateCueUseCaseError.cueNotFound(unknownID) {}
    }

    // MARK: - insertForUndo

    func test_insertForUndo_reinsertsExactCueAtOriginalIndex() async throws {
        let first = Self.makeCue(title: "First", startSeconds: 10)
        let second = Self.makeCue(title: "Second", startSeconds: 50)
        let third = Self.makeCue(title: "Third", startSeconds: 90)
        let project = Self.makeProject(cues: [first, second, third])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)
        try await useCase.delete(projectID: project.id, cueID: second.id)

        let reinserted = try await useCase.insertForUndo(projectID: project.id, cue: second, atIndex: 1)

        XCTAssertEqual(reinserted.id, second.id)
        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [first.id, second.id, third.id])
    }

    func test_insertForUndo_indexPastEnd_clampsToAppend() async throws {
        let first = Self.makeCue(title: "First", startSeconds: 10)
        let second = Self.makeCue(title: "Second", startSeconds: 50)
        let project = Self.makeProject(cues: [first])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        _ = try await useCase.insertForUndo(projectID: project.id, cue: second, atIndex: 99)

        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [first.id, second.id])
    }
}
