import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `UpdateRightHolderDirectoryUseCase` against the real
/// `InMemoryProjectRepository` fake — pure orchestration, no separate pure
/// half to test in `ACCoreTests` (`CONTRIBUTING.md` §5).
final class UpdateRightHolderDirectoryUseCaseTests: XCTestCase {
    private static func makeProject(people: [Person] = [], labels: [Label] = []) -> Project {
        Project(
            name: "Reel One",
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
            ),
            people: people,
            labels: labels
        )
    }

    // MARK: - savePerson

    func test_savePerson_withNewID_appendsAndPersists() async throws {
        let project = Self.makeProject()
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let person = Person(firstName: "Ada", lastName: "Lovelace")

        let result = try await useCase.savePerson(person, in: project.id)

        guard case let .saved(updated) = result else {
            return XCTFail("expected .saved, got \(result)")
        }
        XCTAssertEqual(updated.people, [person])
        XCTAssertGreaterThan(updated.updatedAt, project.updatedAt)
        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [person])
    }

    func test_savePerson_withExistingID_replacesInPlace_preservingOrder() async throws {
        let first = Person(firstName: "Ada", lastName: "Lovelace")
        let second = Person(firstName: "Grace", lastName: "Hopper")
        let project = Self.makeProject(people: [first, second])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let editedFirst = Person(id: first.id, firstName: "Ada", lastName: "Byron", ipiNumber: "00123456789")

        let result = try await useCase.savePerson(editedFirst, in: project.id)

        guard case let .saved(updated) = result else {
            return XCTFail("expected .saved, got \(result)")
        }
        XCTAssertEqual(updated.people, [editedFirst, second])
    }

    func test_savePerson_leavesLabelsUntouched() async throws {
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let project = Self.makeProject(labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)

        _ = try await useCase.savePerson(Person(firstName: "Ada", lastName: "Lovelace"), in: project.id)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.labels, [label])
    }

    // MARK: - saveLabel

    func test_saveLabel_withNewID_appendsAndPersists() async throws {
        let project = Self.makeProject()
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )

        let result = try await useCase.saveLabel(label, in: project.id)

        guard case let .saved(updated) = result else {
            return XCTFail("expected .saved, got \(result)")
        }
        XCTAssertEqual(updated.labels, [label])
        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.labels, [label])
    }

    func test_saveLabel_withExistingID_replacesInPlace() async throws {
        let address = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        let label = Label(name: "Studio AG", address: address)
        let project = Self.makeProject(labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let editedLabel = Label(id: label.id, name: "Studio AG International", address: address)

        let result = try await useCase.saveLabel(editedLabel, in: project.id)

        guard case let .saved(updated) = result else {
            return XCTFail("expected .saved, got \(result)")
        }
        XCTAssertEqual(updated.labels, [editedLabel])
    }

    func test_saveLabel_leavesPeopleUntouched() async throws {
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let project = Self.makeProject(people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let address = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")

        _ = try await useCase.saveLabel(Label(name: "Studio AG", address: address), in: project.id)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [person])
    }

    // MARK: - Not found

    func test_savePerson_unknownProjectID_throwsProjectNotFoundError() async {
        let repository = InMemoryProjectRepository()
        let useCase = UpdateRightHolderDirectoryUseCase(projectRepository: repository)
        let unknownID = UUID()

        do {
            _ = try await useCase.savePerson(Person(firstName: "Ada", lastName: "Lovelace"), in: unknownID)
            XCTFail("Expected ProjectNotFoundError")
        } catch let error as ProjectNotFoundError {
            XCTAssertEqual(error.projectID, unknownID)
        } catch {
            XCTFail("Expected ProjectNotFoundError, got \(error)")
        }
    }
}
