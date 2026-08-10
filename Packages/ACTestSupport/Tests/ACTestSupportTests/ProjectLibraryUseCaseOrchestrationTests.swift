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
}
