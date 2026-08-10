import ACCore
@testable import ACTestSupport
import XCTest

/// Proves `InMemoryProjectRepository` actually behaves like the protocol it
/// fakes — create → appears in fetch-all → delete → gone, per `ROADMAP.md`
/// T3.4 — so later Deliverables' ViewModel tests can trust it without
/// re-verifying this themselves.
final class InMemoryProjectRepositoryTests: XCTestCase {
    private static func makeProject(name: String = "Reel One") -> Project {
        Project(
            name: name,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: Setup(
                title: "A Swiss Story",
                producer: [.person(UUID())],
                directorOrPrincipal: [.person(UUID())],
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: MediaDuration(seconds: 600),
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarant: .person(UUID()),
                declarationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    func test_create_thenFetchAll_includesTheCreatedProject() async throws {
        let repository = InMemoryProjectRepository()
        let project = Self.makeProject()

        try await repository.create(project)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all, [project])
    }

    func test_fetchByID_returnsTheMatchingProject() async throws {
        let repository = InMemoryProjectRepository()
        let project = Self.makeProject()
        try await repository.create(project)

        let fetched = try await repository.fetch(id: project.id)

        XCTAssertEqual(fetched, project)
    }

    func test_fetchByID_returnsNilForAnUnknownID() async throws {
        let repository = InMemoryProjectRepository()
        let fetched = try await repository.fetch(id: UUID())
        XCTAssertNil(fetched)
    }

    func test_update_replacesTheStoredProject() async throws {
        let repository = InMemoryProjectRepository()
        let project = Self.makeProject(name: "Reel One")
        try await repository.create(project)

        let renamed = Project(
            id: project.id,
            name: "Reel One (Renamed)",
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: project.setup
        )
        try await repository.update(renamed)

        let fetched = try await repository.fetch(id: project.id)
        XCTAssertEqual(fetched?.name, "Reel One (Renamed)")
    }

    func test_delete_removesTheProject() async throws {
        let repository = InMemoryProjectRepository()
        let project = Self.makeProject()
        try await repository.create(project)

        try await repository.delete(id: project.id)

        let all = try await repository.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    func test_seedingAtInit_isReflectedInFetchAll() async throws {
        let project = Self.makeProject()
        let repository = InMemoryProjectRepository(projects: [project])

        let all = try await repository.fetchAll()
        XCTAssertEqual(all, [project])
    }

    func test_observeAll_emitsAFreshSnapshotAfterEveryMutation() async throws {
        let repository = InMemoryProjectRepository()
        var iterator = repository.observeAll().makeAsyncIterator()

        // Initial snapshot on subscribe.
        let initial = await iterator.next()
        XCTAssertEqual(initial, [])

        let project = Self.makeProject()
        try await repository.create(project)
        let afterCreate = await iterator.next()
        XCTAssertEqual(afterCreate, [project])

        try await repository.delete(id: project.id)
        let afterDelete = await iterator.next()
        XCTAssertEqual(afterDelete, [])
    }

    func test_observeAll_supportsMultipleIndependentSubscribers() async throws {
        // The shape D11's cross-ViewModel propagation test relies on: two
        // subscribers against the same repository instance, both seeing the
        // same mutation.
        let repository = InMemoryProjectRepository()
        var firstSubscriber = repository.observeAll().makeAsyncIterator()
        var secondSubscriber = repository.observeAll().makeAsyncIterator()

        _ = await firstSubscriber.next()
        _ = await secondSubscriber.next()

        let project = Self.makeProject()
        try await repository.create(project)

        let firstUpdate = await firstSubscriber.next()
        let secondUpdate = await secondSubscriber.next()

        XCTAssertEqual(firstUpdate, [project])
        XCTAssertEqual(secondUpdate, [project])
    }
}
