import ACCore
@testable import ACFeatures
import ACTestSupport
import XCTest

@MainActor
final class RightHolderDirectoryViewModelTests: XCTestCase {
    private func makeProject(
        producer: Party = .person(UUID()),
        people: [Person] = [],
        labels: [Label] = []
    ) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(),
            updatedAt: Date(),
            setup: Setup(
                title: "A Swiss Story",
                producer: [producer],
                directorOrPrincipal: [.person(UUID())],
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .notKnown,
                productionTypes: [.documentaryFilm],
                declarant: .person(UUID()),
                declarationDate: Date(timeIntervalSince1970: 0)
            ),
            people: people,
            labels: labels
        )
    }

    private func makeViewModel(
        project: Project,
        repository: InMemoryProjectRepository
    ) -> RightHolderDirectoryViewModel {
        RightHolderDirectoryViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository),
            updateRightHolderDirectoryUseCase: UpdateRightHolderDirectoryUseCase(projectRepository: repository),
            deleteRightHolderUseCase: DeleteRightHolderUseCase(projectRepository: repository)
        )
    }

    func test_loadDirectory_populatesPeopleAndLabels() async {
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let label = Label(
            name: "Studio AG",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let project = makeProject(people: [person], labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        await viewModel.loadDirectory()

        XCTAssertEqual(viewModel.people, [person])
        XCTAssertEqual(viewModel.labels, [label])
    }

    func test_savePerson_addsToTheDirectoryAndPersists() async throws {
        let project = makeProject()
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        let result = await viewModel.savePerson(Person(firstName: "Ada", lastName: "Lovelace"))

        guard case .saved = result else {
            return XCTFail("expected .saved, got \(String(describing: result))")
        }
        XCTAssertEqual(viewModel.people.map(\.firstName), ["Ada"])
        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.people.map(\.firstName), ["Ada"])
    }

    func test_saveLabel_addsToTheDirectoryAndPersists() async {
        let project = makeProject()
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()
        let address = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")

        let result = await viewModel.saveLabel(Label(name: "Studio AG", address: address))

        guard case .saved = result else {
            return XCTFail("expected .saved, got \(String(describing: result))")
        }
        XCTAssertEqual(viewModel.labels.map(\.name), ["Studio AG"])
    }

    /// Reproduces the reported bug: re-adding a `Person` under a name that
    /// already exists in the directory must be flagged, not silently
    /// duplicated (`docs/DECISIONS.md`).
    func test_savePerson_withADuplicateName_isBlocked_andDoesNotAddASecondEntry() async {
        let existing = Person(firstName: "Ada", lastName: "Lovelace")
        let project = makeProject(people: [existing])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        // Case/whitespace-insensitive: a real duplicate-entry mistake rarely
        // types the name with byte-identical casing/spacing.
        let result = await viewModel.savePerson(Person(firstName: " ada ", lastName: " LOVELACE "))

        guard case let .duplicateName(matched) = result else {
            return XCTFail("expected .duplicateName, got \(String(describing: result))")
        }
        XCTAssertEqual(matched, existing)
        XCTAssertEqual(viewModel.people, [existing], "no second entry should have been added")
    }

    /// Editing an existing `Person` (same id) must not be blocked as a
    /// "duplicate" of itself.
    func test_savePerson_editingTheSameEntry_isNotTreatedAsADuplicate() async {
        let existing = Person(firstName: "Ada", lastName: "Lovelace")
        let project = makeProject(people: [existing])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        let edited = Person(id: existing.id, firstName: "Ada", lastName: "Lovelace", ipiNumber: "12345")
        let result = await viewModel.savePerson(edited)

        guard case .saved = result else {
            return XCTFail("expected .saved, got \(String(describing: result))")
        }
        XCTAssertEqual(viewModel.people, [edited])
    }

    func test_saveLabel_withADuplicateName_isBlocked_andDoesNotAddASecondEntry() async {
        let address = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        let existing = Label(name: "Studio AG", address: address)
        let project = makeProject(labels: [existing])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        let result = await viewModel.saveLabel(Label(name: " studio ag ", address: address))

        guard case let .duplicateName(matched) = result else {
            return XCTFail("expected .duplicateName, got \(String(describing: result))")
        }
        XCTAssertEqual(matched, existing)
        XCTAssertEqual(viewModel.labels, [existing], "no second entry should have been added")
    }

    func test_deletePerson_whenUnreferenced_removesFromTheDirectory() async {
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let project = makeProject(people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        await viewModel.deletePerson(person.id)

        XCTAssertTrue(viewModel.people.isEmpty)
        XCTAssertNil(viewModel.blockedDeleteLocations)
    }

    func test_deletePerson_whenReferencedAsSetupProducer_isBlocked_andSurfacesTheLocation() async {
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let project = makeProject(producer: .person(person.id), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        await viewModel.deletePerson(person.id)

        XCTAssertEqual(viewModel.people, [person])
        XCTAssertEqual(viewModel.blockedDeleteLocations, [.setupProducer])
    }

    func test_clearBlockedDeleteLocations_clearsAPreviouslySetBlock() async {
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let project = makeProject(producer: .person(person.id), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()
        await viewModel.deletePerson(person.id)
        XCTAssertNotNil(viewModel.blockedDeleteLocations)

        viewModel.clearBlockedDeleteLocations()

        XCTAssertNil(viewModel.blockedDeleteLocations)
    }

    func test_deleteLabel_whenUnreferenced_removesFromTheDirectory() async {
        let address = PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        let label = Label(name: "Studio AG", address: address)
        let project = makeProject(labels: [label])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.loadDirectory()

        await viewModel.deleteLabel(label.id)

        XCTAssertTrue(viewModel.labels.isEmpty)
    }
}
