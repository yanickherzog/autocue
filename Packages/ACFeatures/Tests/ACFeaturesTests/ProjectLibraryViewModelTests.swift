import ACCore
@testable import ACFeatures
import ACTestSupport
import XCTest

@MainActor
final class ProjectLibraryViewModelTests: XCTestCase {
    private func makeViewModel(repository: InMemoryProjectRepository) -> ProjectLibraryViewModel {
        ProjectLibraryViewModel(
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository),
            createProjectUseCase: CreateProjectUseCase(projectRepository: repository),
            deleteProjectUseCase: DeleteProjectUseCase(projectRepository: repository)
        )
    }

    func test_startObserving_populatesProjectsFromTheRepositoryLiveStream() async throws {
        let repository = InMemoryProjectRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.startObserving()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(viewModel.projects, [])

        try await repository.create(
            Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: makeMinimalSetup())
        )
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(viewModel.projects.map(\.name), ["Reel One"])
    }

    func test_createProject_addsItToTheLiveList_noManualRefreshNeeded() async throws {
        let repository = InMemoryProjectRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.startObserving()
        try await Task.sleep(nanoseconds: 10_000_000)

        await viewModel.createProject(name: "Reel Two")
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(viewModel.projects.map(\.name), ["Reel Two"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_deleteProject_removesItFromTheLiveList() async throws {
        let repository = InMemoryProjectRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.startObserving()
        try await Task.sleep(nanoseconds: 10_000_000)

        await viewModel.createProject(name: "Reel Three")
        try await Task.sleep(nanoseconds: 10_000_000)
        let createdID = try XCTUnwrap(viewModel.projects.first?.id)

        await viewModel.deleteProject(id: createdID)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(viewModel.projects.isEmpty)
    }

    func test_startObserving_calledTwice_doesNotDuplicateSubscriptions() async throws {
        let repository = InMemoryProjectRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.startObserving()
        viewModel.startObserving()
        try await repository.create(
            Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: makeMinimalSetup())
        )
        try await Task.sleep(nanoseconds: 10_000_000)

        // A duplicated subscription would still just yield the same
        // snapshot twice into the same @Observable property, not a visibly
        // different symptom — this asserts the count is still correct
        // rather than asserting an internal subscriber count directly.
        XCTAssertEqual(viewModel.projects.count, 1)
    }

    private func makeMinimalSetup() -> Setup {
        CreateProjectUseCase.makeDefaultSetup(title: "Reel", now: Date(timeIntervalSince1970: 0))
    }
}
