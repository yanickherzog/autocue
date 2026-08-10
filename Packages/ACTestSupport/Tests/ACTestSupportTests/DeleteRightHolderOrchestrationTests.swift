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
                producer: [producer],
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

    func test_deletePerson_whenUnreferenced_removesThemAndPersists() async throws {
        let person = Person(firstName: "Anna", lastName: "Muster")
        let project = Self.makeProject(producer: .person(UUID()), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)

        let result = try await useCase.deletePerson(person.id, from: project.id, settings: Settings())

        guard case let .deleted(updatedProject) = result else {
            return XCTFail("Expected .deleted, got \(result)")
        }
        XCTAssertTrue(updatedProject.people.isEmpty)
        // A successful deletion is a real mutation to the Project's data
        // (SPEC.md §4.1) — updatedAt must advance, the same as any other
        // write through ProjectRepository.
        XCTAssertGreaterThan(updatedProject.updatedAt, project.updatedAt)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [])
        XCTAssertGreaterThan(persisted?.updatedAt ?? .distantPast, project.updatedAt)
    }

    func test_deletePerson_whenReferencedAsSetupProducer_isBlockedAndNotPersisted() async throws {
        let person = Person(firstName: "Anna", lastName: "Muster")
        let project = Self.makeProject(producer: .person(person.id), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)

        let result = try await useCase.deletePerson(person.id, from: project.id, settings: Settings())

        XCTAssertEqual(result, .blocked([.setupProducer]))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [person])
        // Nothing was mutated or persisted, so updatedAt must stay untouched.
        XCTAssertEqual(persisted?.updatedAt, project.updatedAt)
    }

    func test_deleteLabel_whenUnreferenced_removesThemAndPersists() async throws {
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let project = Self.makeProject(producer: .person(UUID()), labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = DeleteRightHolderUseCase(projectRepository: repository)

        let result = try await useCase.deleteLabel(label.id, from: project.id, settings: Settings())

        guard case let .deleted(updatedProject) = result else {
            return XCTFail("Expected .deleted, got \(result)")
        }
        XCTAssertTrue(updatedProject.labels.isEmpty)
        XCTAssertGreaterThan(updatedProject.updatedAt, project.updatedAt)
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

        let result = try await useCase.deleteLabel(label.id, from: project.id, settings: settings)

        XCTAssertEqual(result, .blocked([.settingsDefaultDeclarant]))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.labels, [label])
        XCTAssertEqual(persisted?.updatedAt, project.updatedAt)
    }

    // MARK: - Regression: delete must see a Setup-field clear from a different Use Case

    /// Reproduces the exact reported bug: clear `Setup.declarant` via
    /// `UpdateSetupUseCase` (a different Use Case, and in the real app a
    /// different ViewModel — `SetupViewModel`, not
    /// `RightHolderDirectoryViewModel`), then immediately attempt to delete
    /// the now-unreferenced `Person` — must succeed. An earlier version of
    /// `DeleteRightHolderUseCase` took a caller-supplied `Project` snapshot
    /// rather than fetching fresh, which is exactly what let this fail: the
    /// caller (`RightHolderDirectoryViewModel`) had no way to know the
    /// Setup-driven clear had happened.
    func test_deletePerson_immediatelyAfterClearingTheOnlyReferencingSetupField_succeeds() async throws {
        let person = Person(firstName: "Anna", lastName: "Muster")
        let project = Self.makeProject(producer: .person(UUID()), people: [person])
        // `declarant` is the reference under test; overwrite it onto the
        // fixture's own default declarant so the only reference to `person`
        // is the one this test clears.
        let projectWithPersonAsDeclarant = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: project.setup.updating(declarant: .some(.person(person.id))),
            people: project.people
        )
        let repository = InMemoryProjectRepository(projects: [projectWithPersonAsDeclarant])
        let setupUseCase = UpdateSetupUseCase(projectRepository: repository)
        let deleteUseCase = DeleteRightHolderUseCase(projectRepository: repository)

        // Confirm the delete is genuinely blocked before the clear — proves
        // the reference really was in place, not a test fixture that never
        // exercised the guard at all.
        let blockedResult = try await deleteUseCase.deletePerson(person.id, from: project.id, settings: Settings())
        XCTAssertEqual(blockedResult, .blocked([.setupDeclarant]))

        try await setupUseCase.update(
            projectID: project.id,
            setup: projectWithPersonAsDeclarant.setup.updating(declarant: .some(nil))
        )

        // The regression: this must now succeed, reading the truly-current
        // (post-clear) Setup, not a stale pre-clear snapshot.
        let result = try await deleteUseCase.deletePerson(person.id, from: project.id, settings: Settings())

        guard case let .deleted(updated) = result else {
            return XCTFail("expected .deleted once the only reference was cleared, got \(result)")
        }
        XCTAssertTrue(updated.people.isEmpty)
        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people, [])
    }
}
