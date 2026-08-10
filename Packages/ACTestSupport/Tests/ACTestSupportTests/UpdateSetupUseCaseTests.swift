import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `UpdateSetupUseCase` against the real `InMemoryProjectRepository`
/// fake — this Use Case is pure orchestration (fetch, replace one slice,
/// persist), with no pure half to test separately in `ACCoreTests`
/// (`CONTRIBUTING.md` §5).
final class UpdateSetupUseCaseTests: XCTestCase {
    private static func makeSetup(title: String = "A Swiss Story") -> Setup {
        Setup(
            title: title,
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
    }

    private static func makeProject(people: [Person] = [], labels: [Label] = []) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: makeSetup(),
            people: people,
            labels: labels
        )
    }

    func test_update_replacesTheSetupAndPersists() async throws {
        let project = Self.makeProject()
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateSetupUseCase(projectRepository: repository)
        let newSetup = Self.makeSetup(title: "The Great Swiss Film")

        try await useCase.update(projectID: project.id, setup: newSetup)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.setup.title, "The Great Swiss Film")
        XCTAssertGreaterThan(persisted?.updatedAt ?? .distantPast, project.updatedAt)
    }

    func test_update_leavesPeopleAndLabelsUntouched() async throws {
        // The disjoint-slice guarantee UpdateSetupUseCase's doc comment
        // describes: a Setup edit must never clobber a concurrent
        // RightHolderDirectoryViewModel-driven change to people/labels.
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let project = Self.makeProject(people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateSetupUseCase(projectRepository: repository)

        try await useCase.update(projectID: project.id, setup: Self.makeSetup(title: "New Title"))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [person])
    }

    func test_update_fetchesFreshRatherThanClobberingAConcurrentDirectoryChange() async throws {
        // Simulates the concurrent-write scenario directly: a
        // RightHolderDirectoryViewModel-driven save lands on the repository
        // *between* this Use Case's own fetch and its own write would be the
        // dangerous ordering — here it lands before the fetch, which the
        // fetch-fresh design handles correctly by construction.
        let project = Self.makeProject()
        let repository = InMemoryProjectRepository(projects: [project])
        let directoryUseCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let newPerson = Person(firstName: "Grace", lastName: "Hopper")
        try await directoryUseCase.savePerson(newPerson, in: project.id)

        let setupUseCase = UpdateSetupUseCase(projectRepository: repository)
        try await setupUseCase.update(projectID: project.id, setup: Self.makeSetup(title: "New Title"))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.setup.title, "New Title")
        XCTAssertEqual(persisted?.people, [newPerson])
    }

    func test_update_unknownProjectID_throwsProjectNotFoundError() async {
        let repository = InMemoryProjectRepository()
        let useCase = UpdateSetupUseCase(projectRepository: repository)
        let unknownID = UUID()

        do {
            try await useCase.update(projectID: unknownID, setup: Self.makeSetup())
            XCTFail("Expected ProjectNotFoundError")
        } catch let error as ProjectNotFoundError {
            XCTAssertEqual(error.projectID, unknownID)
        } catch {
            XCTFail("Expected ProjectNotFoundError, got \(error)")
        }
    }
}
