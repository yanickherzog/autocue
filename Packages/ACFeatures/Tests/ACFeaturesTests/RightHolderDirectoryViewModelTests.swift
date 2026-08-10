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
                producer: producer,
                directorOrPrincipal: .person(UUID()),
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

        let saved = await viewModel.savePerson(Person(firstName: "Ada", lastName: "Lovelace"))

        XCTAssertTrue(saved)
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

        let saved = await viewModel.saveLabel(Label(name: "Studio AG", address: address))

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.labels.map(\.name), ["Studio AG"])
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
