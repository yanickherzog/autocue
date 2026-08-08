import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `DeleteRightHolderUseCase`'s repository-touching orchestration
/// half (`deletePerson`/`deleteLabel`) against the real
/// `InMemoryProjectRepository` fake — the guard-scan half is already fully
/// covered, mock-free, in `ACCoreTests` (`CONTRIBUTING.md` §5); this proves
/// the fake actually works correctly with real Use Case code end-to-end, per
/// `ROADMAP.md` T3.4's stated purpose.
final class DeleteRightHolderOrchestrationTests: XCTestCase {
    private static func makeProject(
        producer: Party,
        people: [Person] = [],
        labels: [Label] = []
    ) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: Setup(
                title: "A Swiss Story",
                producer: producer,
                directorOrPrincipal: .person(UUID()),
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: MediaDuration(seconds: 600),
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarant: .person(UUID()),
                declarationDate: Date(timeIntervalSince1970: 0)
            ),
            people: people,
            labels: labels
        )
    }

    func test_deletePerson_whenUnreferenced_removesThemAndPersists() async throws {
        let person = Person(firstName: "Anna", lastName: "Muster")
        let project = Self.makeProject(producer: .person(UUID()), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)

        let result = try await useCase.deletePerson(person.id, from: project, settings: Settings())

        guard case let .deleted(updatedProject) = result else {
            return XCTFail("Expected .deleted, got \(result)")
        }
        XCTAssertTrue(updatedProject.people.isEmpty)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [])
    }

    func test_deletePerson_whenReferencedAsSetupProducer_isBlockedAndNotPersisted() async throws {
        let person = Person(firstName: "Anna", lastName: "Muster")
        let project = Self.makeProject(producer: .person(person.id), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)

        let result = try await useCase.deletePerson(person.id, from: project, settings: Settings())

        XCTAssertEqual(result, .blocked([.setupProducer]))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [person])
    }

    func test_deleteLabel_whenUnreferenced_removesThemAndPersists() async throws {
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let project = Self.makeProject(producer: .person(UUID()), labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)

        let result = try await useCase.deleteLabel(label.id, from: project, settings: Settings())

        guard case let .deleted(updatedProject) = result else {
            return XCTFail("Expected .deleted, got \(result)")
        }
        XCTAssertTrue(updatedProject.labels.isEmpty)
    }

    func test_deleteLabel_whenReferencedAsSettingsDefaultDeclarant_isBlockedAndNotPersisted() async throws {
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let project = Self.makeProject(producer: .person(UUID()), labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)
        let settings = Settings(defaultDeclarant: .label(label.id))

        let result = try await useCase.deleteLabel(label.id, from: project, settings: settings)

        XCTAssertEqual(result, .blocked([.settingsDefaultDeclarant]))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.labels, [label])
    }
}
