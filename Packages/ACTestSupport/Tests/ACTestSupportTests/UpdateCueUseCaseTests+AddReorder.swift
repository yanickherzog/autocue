import ACCore
@testable import ACTestSupport
import XCTest

/// `add`/`reorder` (`UpdateCueUseCase`'s D10/T10.1 remaining scope, once
/// `edit`/`split`/`merge`/`delete`/`insertForUndo`/`moveBoundary` were all
/// pulled forward during D9 — see `docs/DECISIONS.md`) — split into its own
/// file for the same type-body-length-limit reason `+Delete.swift` already
/// is. Reuses `UpdateCueUseCaseTests`'s `makeProject`/`makeCue` helpers.
extension UpdateCueUseCaseTests {
    // MARK: - Add

    func test_add_appendsAFreshManualCue_withPinnedDefaults() async throws {
        let existing = Self.makeCue(title: "First", startSeconds: 10)
        let project = Self.makeProject(cues: [existing])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let added = try await useCase.add(projectID: project.id)

        XCTAssertEqual(added.title, "")
        XCTAssertEqual(added.duration, .zero)
        XCTAssertEqual(added.rightHolders, [])
        XCTAssertEqual(added.source, .manual)
        XCTAssertNil(added.startTimecode)
        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [existing.id, added.id])
    }

    func test_add_unknownProjectID_throwsProjectNotFound() async throws {
        let repository = InMemoryProjectRepository(projects: [])
        let useCase = UpdateCueUseCase(projectRepository: repository)
        let unknownID = Project.ID()

        do {
            try await useCase.add(projectID: unknownID)
            XCTFail("Expected ProjectNotFoundError")
        } catch is ProjectNotFoundError {}
    }

    // MARK: - Reorder

    func test_reorder_movingLaterCueEarlier_reordersWithNoFieldChanges() async throws {
        let first = Self.makeCue(title: "First", startSeconds: 10)
        let second = Self.makeCue(title: "Second", startSeconds: 50)
        let third = Self.makeCue(title: "Third", startSeconds: 90)
        let project = Self.makeProject(cues: [first, second, third])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let reordered = try await useCase.reorder(projectID: project.id, cueID: third.id, toIndex: 0)

        XCTAssertEqual(reordered.map(\.id), [third.id, first.id, second.id])
        // No field on the moved cue changed -- in particular, `source` was
        // never reclassified, unlike every other structural mutation in
        // this file (SPEC.md §4.1: order isn't a stored field on `Cue`).
        XCTAssertEqual(reordered.first, third)
    }

    func test_reorder_movingEarlierCueLater_reordersCorrectly() async throws {
        let first = Self.makeCue(title: "First", startSeconds: 10)
        let second = Self.makeCue(title: "Second", startSeconds: 50)
        let third = Self.makeCue(title: "Third", startSeconds: 90)
        let project = Self.makeProject(cues: [first, second, third])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let reordered = try await useCase.reorder(projectID: project.id, cueID: first.id, toIndex: 2)

        XCTAssertEqual(reordered.map(\.id), [second.id, third.id, first.id])
    }

    func test_reorder_toIndexPastEnd_clampsToAppend() async throws {
        let first = Self.makeCue(title: "First", startSeconds: 10)
        let second = Self.makeCue(title: "Second", startSeconds: 50)
        let project = Self.makeProject(cues: [first, second])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let reordered = try await useCase.reorder(projectID: project.id, cueID: first.id, toIndex: 99)

        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
    }

    func test_reorder_unknownCueID_throwsCueNotFound() async throws {
        let project = Self.makeProject(cues: [])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)
        let unknownID = UUID()

        do {
            try await useCase.reorder(projectID: project.id, cueID: unknownID, toIndex: 0)
            XCTFail("Expected cueNotFound")
        } catch UpdateCueUseCaseError.cueNotFound(unknownID) {}
    }
}
