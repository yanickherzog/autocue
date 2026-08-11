import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `ObserveProjectsUseCase`/`CreateProjectUseCase`/
/// `DeleteProjectUseCase`'s repository-touching orchestration against the
/// real `InMemoryProjectRepository` fake (`ROADMAP.md` D6/T6.2) — the same
/// split `DeleteRightHolderUseCaseTests`/`DeleteRightHolderOrchestrationTests`
/// already establish between an `ACCore`-level pure test and an
/// `ACTestSupport`-level orchestration test.
final class ProjectLibraryUseCaseOrchestrationTests: XCTestCase {
    func test_create_persistsAndReturnsTheNewProject() async throws {
        let repository = InMemoryProjectRepository()
        let useCase = CreateProjectUseCase(projectRepository: repository)

        let created = try await useCase.create(name: "Reel One")

        XCTAssertEqual(created.name, "Reel One")
        XCTAssertEqual(created.setup.title, "Reel One")
        let persisted = try await repository.fetch(id: created.id)
        XCTAssertEqual(persisted, created)
    }

    func test_delete_removesAPersistedProject() async throws {
        let repository = InMemoryProjectRepository()
        let createUseCase = CreateProjectUseCase(projectRepository: repository)
        let deleteUseCase = DeleteProjectUseCase(projectRepository: repository)
        let created = try await createUseCase.create(name: "Reel One")

        try await deleteUseCase.delete(id: created.id)

        let persisted = try await repository.fetch(id: created.id)
        XCTAssertNil(persisted)
    }

    func test_observeAll_emitsANewSnapshotAfterCreate() async throws {
        let repository = InMemoryProjectRepository()
        let observeUseCase = ObserveProjectsUseCase(projectRepository: repository)
        let createUseCase = CreateProjectUseCase(projectRepository: repository)

        var iterator = observeUseCase.observeAll().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial, [])

        try await createUseCase.create(name: "Reel One")

        let afterCreate = await iterator.next()
        XCTAssertEqual(afterCreate?.count, 1)
        XCTAssertEqual(afterCreate?.first?.name, "Reel One")
    }

    /// Regression test for a real `ProjectNotFoundError` bug found during
    /// normal use (`ROADMAP.md` D7, later round): close a Project window,
    /// delete that Project from the Library, then create a new one — the new
    /// project's window landed on the *old*, now-deleted Project's ID.
    /// Investigation (`docs/DECISIONS.md`) ruled out every hypothesis at this
    /// Use Case/Repository layer — `CreateProjectUseCase`/`Project.init`
    /// always mint a genuinely fresh `UUID`, and `ProjectRepositoryImpl`
    /// correctly republishes its live snapshot after both create and delete —
    /// so this test exists to keep that guarantee airtight going forward,
    /// even though the actual observed bug lived one layer up, in SwiftUI's
    /// own `WindowGroup(for:)` view-identity reuse (fixed via `.id(projectID)`
    /// in `AutoCueApp.swift`, not testable from here). Exercises the exact
    /// repro sequence: create A, delete A, create B — B must get its own
    /// fresh identity, A must be genuinely gone, and a fetch by A's old ID
    /// must come back `nil` rather than resurrecting stale data (the
    /// Repository-layer equivalent of `SetupViewModel.projectNotFound`,
    /// exercised directly against `SetupViewModelTests`
    /// `.test_load_projectDoesNotExist_setsProjectNotFound_andReturns`).
    func test_repro_createDeleteThenCreateAgain_newProjectGetsAGenuinelyFreshIdentity() async throws {
        let repository = InMemoryProjectRepository()
        let createUseCase = CreateProjectUseCase(projectRepository: repository)
        let deleteUseCase = DeleteProjectUseCase(projectRepository: repository)
        let observeUseCase = ObserveProjectsUseCase(projectRepository: repository)

        let projectA = try await createUseCase.create(name: "Reel One")
        try await deleteUseCase.delete(id: projectA.id)
        let projectB = try await createUseCase.create(name: "Reel Two")

        XCTAssertNotEqual(projectB.id, projectA.id)

        let fetchedA = try await repository.fetch(id: projectA.id)
        XCTAssertNil(fetchedA, "the deleted project must never resurface, not even under a stale ID lookup")

        let fetchedB = try await repository.fetch(id: projectB.id)
        XCTAssertEqual(fetchedB, projectB)

        var iterator = observeUseCase.observeAll().makeAsyncIterator()
        let snapshot = await iterator.next()
        XCTAssertEqual(snapshot?.map(\.id), [projectB.id])
    }
}
