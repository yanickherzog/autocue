@testable import ACCore
@testable import ACPersistence
import SwiftData
import XCTest

final class ProjectRepositoryImplTests: XCTestCase {
    // MARK: - CRUD

    func test_createThenFetchByIDReturnsTheProject() async throws {
        let repository = try makeRepository()
        let project = ProjectFixture.makeMinimal(name: "created")

        try await repository.create(project)

        let fetched = try await repository.fetch(id: project.id)
        XCTAssertEqual(fetched, project)
    }

    func test_fetchAllReturnsEveryCreatedProject() async throws {
        let repository = try makeRepository()
        let first = ProjectFixture.makeMinimal(name: "first")
        let second = ProjectFixture.makeMinimal(name: "second")

        try await repository.create(first)
        try await repository.create(second)

        let all = try await repository.fetchAll()
        XCTAssertEqual(Set(all.map(\.id)), Set([first.id, second.id]))
    }

    func test_fetchByIDReturnsNilForUnknownID() async throws {
        let repository = try makeRepository()
        let fetched = try await repository.fetch(id: UUID())
        XCTAssertNil(fetched)
    }

    func test_updateReplacesThePersistedProject() async throws {
        let repository = try makeRepository()
        let original = ProjectFixture.makeMinimal(name: "original")
        try await repository.create(original)

        let renamed = Project(
            id: original.id,
            name: "renamed",
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_699_999_999),
            setup: original.setup
        )
        try await repository.update(renamed)

        let fetched = try await repository.fetch(id: original.id)
        XCTAssertEqual(fetched?.name, "renamed")
    }

    func test_deleteRemovesTheProject() async throws {
        let repository = try makeRepository()
        let project = ProjectFixture.makeMinimal(name: "to-delete")
        try await repository.create(project)

        try await repository.delete(id: project.id)

        let fetched = try await repository.fetch(id: project.id)
        XCTAssertNil(fetched)
    }

    func test_deleteOfUnknownIDDoesNotThrow() async throws {
        let repository = try makeRepository()
        try await repository.delete(id: UUID())
    }

    // MARK: - observeAll()

    func test_observeAllEmitsAfterEveryMutatingCall() async throws {
        let repository = try makeRepository()
        var iterator = repository.observeAll().makeAsyncIterator()

        // Initial subscribe emits the (empty) current snapshot.
        let initial = await iterator.next()
        XCTAssertEqual(initial, [])

        let project = ProjectFixture.makeMinimal(name: "observed")
        try await repository.create(project)
        let afterCreate = await iterator.next()
        XCTAssertEqual(afterCreate?.map(\.id), [project.id])

        let renamed = Project(
            id: project.id,
            name: "renamed",
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: project.setup
        )
        try await repository.update(renamed)
        let afterUpdate = await iterator.next()
        XCTAssertEqual(afterUpdate?.first?.name, "renamed")

        try await repository.delete(id: project.id)
        let afterDelete = await iterator.next()
        XCTAssertEqual(afterDelete, [])
    }

    func test_observeAllSupportsMultipleConcurrentSubscribers() async throws {
        let repository = try makeRepository()
        var firstIterator = repository.observeAll().makeAsyncIterator()
        var secondIterator = repository.observeAll().makeAsyncIterator()

        _ = await firstIterator.next()
        _ = await secondIterator.next()

        let project = ProjectFixture.makeMinimal(name: "shared")
        try await repository.create(project)

        let firstUpdate = await firstIterator.next()
        let secondUpdate = await secondIterator.next()
        XCTAssertEqual(firstUpdate?.map(\.id), [project.id])
        XCTAssertEqual(secondUpdate?.map(\.id), [project.id])
    }

    // MARK: - Concurrency: per-Project.ID write serialization

    /// D4's acceptance criterion: two concurrent saves to the *same*
    /// `Project.ID` serialize correctly (second waits for first, neither is
    /// lost). Deterministic via `Signal`, not wall-clock timing — see
    /// `Signal`'s doc comment.
    func test_sameProjectIDWritesSerializeAndPreserveSubmissionOrder() async throws {
        let repository = try makeRepository()
        let projectID = UUID()
        let firstEntered = Signal()
        let releaseFirst = Signal()

        await repository.setWriteHook { id in
            guard id == projectID else { return }
            await firstEntered.fire()
            await releaseFirst.wait()
        }

        let firstTask = Task {
            try await repository.create(ProjectFixture.makeMinimal(id: projectID, name: "first"))
        }
        // Confirms the first write is now genuinely blocked inside its own
        // dispatched Task, holding projectID's write tail, before the second
        // write is even submitted — this is what makes the ordering below
        // deterministic rather than a timing gamble.
        await firstEntered.wait()

        let secondTask = Task {
            try await repository.update(ProjectFixture.makeMinimal(id: projectID, name: "second"))
        }

        await releaseFirst.fire()
        try await firstTask.value
        try await secondTask.value

        let final = try await repository.fetch(id: projectID)
        XCTAssertEqual(final?.name, "second")
    }

    /// D4's acceptance criterion: saves to *different* `Project.ID`s do not
    /// block each other. If this regressed to naive whole-actor
    /// serialization, this test would hang until the suite's timeout rather
    /// than fail fast — that's an acceptable trade-off for a genuinely
    /// deterministic proof of non-blocking (no sleep-based approximation).
    func test_differentProjectIDWritesDoNotBlockEachOther() async throws {
        let repository = try makeRepository()
        let idA = UUID()
        let idB = UUID()
        let aEntered = Signal()
        let releaseA = Signal()

        await repository.setWriteHook { id in
            guard id == idA else { return }
            await aEntered.fire()
            await releaseA.wait()
        }

        let taskA = Task {
            try await repository.create(ProjectFixture.makeMinimal(id: idA, name: "a"))
        }
        await aEntered.wait() // A is now blocked, holding only idA's write tail.

        // B must complete without waiting for A to be released.
        try await repository.create(ProjectFixture.makeMinimal(id: idB, name: "b"))
        let bResult = try await repository.fetch(id: idB)
        XCTAssertNotNil(bResult, "different Project.ID write must not block on an unrelated in-flight write")

        await releaseA.fire()
        try await taskA.value
        let aResult = try await repository.fetch(id: idA)
        XCTAssertNotNil(aResult)
    }

    // MARK: - Helpers

    private func makeRepository() throws -> ProjectRepositoryImpl {
        try ProjectRepositoryImpl(modelContainer: makeInMemoryContainer())
    }
}
