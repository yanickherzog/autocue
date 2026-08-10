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

    // MARK: - Concurrency: update(id:transform:) closes the fetch-then-write race

    /// Reproduces the exact shape of the confirmed D7 data-loss bug:
    /// `UpdateSetupUseCase` and `UpdateRightHolderDirectoryUseCase` each
    /// mutate a disjoint slice (`setup` vs. `people`) of the *same*
    /// `Project`, concurrently, from the same Project window. With plain
    /// fetch-then-`update(_:)` (the pre-fix shape), the second write's fetch
    /// can land before the first write does, so the second write persists a
    /// `Project` built from stale data and silently discards the first
    /// write's change. This test drives two concurrent
    /// `update(id:transform:)` calls through that exact interleaving —
    /// deterministically, via `Signal`/`setWriteHook`, not wall-clock timing
    /// — and asserts *both* slices survive, proving `update(id:transform:)`
    /// actually closes the gap rather than merely compiling.
    func test_concurrentAtomicUpdatesToDisjointSlicesBothSurvive() async throws {
        let repository = try makeRepository()
        let projectID = UUID()
        try await repository.create(ProjectFixture.makeMinimal(id: projectID, name: "original"))

        let firstEntered = Signal()
        let releaseFirst = Signal()
        let pauseGate = PauseOnceGate()

        // Pauses only the *first* write's dispatched work to reach this
        // point — the second, chained write must run only after the first
        // one has actually completed and persisted, at which point the hook
        // is a no-op and it proceeds straight through.
        await repository.setWriteHook { id in
            guard id == projectID, await pauseGate.shouldPauseOnce() else { return }
            await firstEntered.fire()
            await releaseFirst.wait()
        }

        let addPersonTask = Task {
            try await repository.update(id: projectID) { project in
                Project(
                    id: project.id,
                    name: project.name,
                    createdAt: project.createdAt,
                    updatedAt: project.updatedAt,
                    setup: project.setup,
                    cues: project.cues,
                    people: project.people + [Person(firstName: "Ada", lastName: "Lovelace")],
                    labels: project.labels
                )
            }
        }
        // Confirms the first update is genuinely blocked *inside* its own
        // dispatched write, holding projectID's write tail, before the
        // second update is even submitted.
        await firstEntered.wait()

        let renameTask = Task {
            try await repository.update(id: projectID) { project in
                Project(
                    id: project.id,
                    name: "renamed",
                    createdAt: project.createdAt,
                    updatedAt: project.updatedAt,
                    setup: project.setup,
                    cues: project.cues,
                    people: project.people,
                    labels: project.labels
                )
            }
        }

        await releaseFirst.fire()
        _ = try await addPersonTask.value
        _ = try await renameTask.value

        let final = try await repository.fetch(id: projectID)
        XCTAssertEqual(final?.name, "renamed", "the rename must not be lost")
        XCTAssertEqual(
            final?.people.map(\.lastName), ["Lovelace"],
            "the concurrently-added Person must not be lost — this is the exact data-loss shape " +
                "update(id:transform:) exists to prevent"
        )
    }

    /// Reproduces the exact reported bug, but as a genuine concurrent
    /// interleaving against the real `ProjectRepositoryImpl` queue (not just
    /// sequential test-code ordering, which `ACTestSupportTests`'
    /// `DeleteRightHolderOrchestrationTests` already covers against the
    /// simpler `InMemoryProjectRepository` fake) — same rigor as
    /// `test_concurrentAtomicUpdatesToDisjointSlicesBothSurvive`, above.
    /// `UpdateSetupUseCase.update` (clearing `Setup.declarant`) is paused
    /// mid-write via `Signal`/`setWriteHook`; `DeleteRightHolderUseCase
    /// .deletePerson` for the now-being-cleared `Person` is submitted while
    /// that clear is still in flight, then the clear is released. Because
    /// both Use Cases now go through the same `update(id:transform:)`
    /// per-`Project.ID` `writeTails` queue, the delete's own fetch (inside
    /// its `transform`) cannot execute until the clear's write has fully
    /// landed — proving the guard-check is race-safe by construction, not
    /// merely correct when called in a conveniently sequential order.
    func test_deletePersonSubmittedWhileAConcurrentSetupClearIsInFlight_seesThePostClearState() async throws {
        let repository = try makeRepository()
        let projectID = UUID()
        let personID = UUID()
        let initialProject = ProjectFixture.makeMinimal(id: projectID, name: "original")
        let clearedSetup = initialProject.setup.updating(declarant: .some(nil))
        let declaredProject = Project(
            id: initialProject.id,
            name: initialProject.name,
            createdAt: initialProject.createdAt,
            updatedAt: initialProject.updatedAt,
            setup: initialProject.setup.updating(declarant: .some(.person(personID))),
            people: [Person(id: personID, firstName: "Anna", lastName: "Muster")]
        )
        try await repository.create(declaredProject)

        let clearEntered = Signal()
        let releaseClear = Signal()
        let pauseGate = PauseOnceGate()

        await repository.setWriteHook { id in
            guard id == projectID, await pauseGate.shouldPauseOnce() else { return }
            await clearEntered.fire()
            await releaseClear.wait()
        }

        let setupUseCase = UpdateSetupUseCase(projectRepository: repository)
        let clearTask = Task {
            try await setupUseCase.update(projectID: projectID, setup: clearedSetup)
        }
        // The clear is now genuinely paused inside its own dispatched write,
        // holding projectID's write tail.
        await clearEntered.wait()

        let deleteUseCase = DeleteRightHolderUseCase(projectRepository: repository)
        let deleteTask = Task {
            try await deleteUseCase.deletePerson(personID, from: projectID, settings: Settings())
        }

        await releaseClear.fire()
        try await clearTask.value
        let deleteResult = try await deleteTask.value

        guard case let .deleted(updated) = deleteResult else {
            return XCTFail(
                "expected .deleted once the concurrent clear landed, got \(deleteResult) — " +
                    "the delete must have seen a stale, pre-clear Setup"
            )
        }
        XCTAssertTrue(updated.people.isEmpty)
        let persisted = try await repository.fetch(id: projectID)
        XCTAssertNil(persisted?.setup.declarant)
        XCTAssertEqual(persisted?.people, [])
    }

    // MARK: - Helpers

    private func makeRepository() throws -> ProjectRepositoryImpl {
        try ProjectRepositoryImpl(modelContainer: makeInMemoryContainer())
    }
}

/// Test-only: lets a `writeHook` pause exactly the *first* write it's
/// invoked for and pass every subsequent one straight through, without
/// capturing a plain mutable `var` in the `@Sendable` hook closure (which
/// would either fail to compile or be a genuine data race under strict
/// concurrency checking).
private actor PauseOnceGate {
    private var hasPausedOnce = false

    func shouldPauseOnce() -> Bool {
        guard !hasPausedOnce else { return false }
        hasPausedOnce = true
        return true
    }
}
