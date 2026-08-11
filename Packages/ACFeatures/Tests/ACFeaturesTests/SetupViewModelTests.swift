import ACCore
@testable import ACFeatures
import ACTestSupport
import XCTest

@MainActor
final class SetupViewModelTests: XCTestCase {
    private func makeSetup(title: String = "A Swiss Story") -> Setup {
        Setup(
            title: title,
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeProject(setup: Setup, people: [Person] = []) -> Project {
        Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: setup, people: people)
    }

    private func makeViewModel(
        project: Project,
        repository: InMemoryProjectRepository,
        debounceNanoseconds: UInt64 = 20_000_000
    ) -> SetupViewModel {
        SetupViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository),
            updateSetupUseCase: UpdateSetupUseCase(projectRepository: repository),
            debounceNanoseconds: debounceNanoseconds
        )
    }

    // MARK: - Construction (no synchronous fetch — see SetupViewModel's doc comment)

    func test_construction_startsWithAPlaceholderEmptySetup_notTheRealPersistedValue() {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        XCTAssertEqual(viewModel.setup.title, "")
    }

    // MARK: - load()

    func test_load_populatesTheRealSetupAndDirectory() async {
        let person = Person(firstName: "Ada", lastName: "Lovelace")
        let project = makeProject(setup: makeSetup(), people: [person])
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.setup.title, "A Swiss Story")
        XCTAssertEqual(viewModel.people, [person])
    }

    func test_load_calledASecondTime_refreshesDirectory_butNeverOverwritesSetupAgain() async {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.load()

        // Simulate an in-progress, not-yet-saved edit, then a directory
        // refresh (e.g. the party picker sheet reappearing) — the edit must
        // survive.
        viewModel.updateDebounced(makeSetup(title: "In Progress Edit"))
        let newPerson = Person(firstName: "Grace", lastName: "Hopper")
        try? await repository.update(
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                setup: project.setup,
                people: [newPerson]
            )
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.setup.title, "In Progress Edit")
        XCTAssertEqual(viewModel.people, [newPerson])
    }

    // MARK: - projectNotFound (ROADMAP.md D7, ProjectNotFoundError regression)

    func test_load_projectDoesNotExist_setsProjectNotFound_andReturns() async {
        let repository = InMemoryProjectRepository(projects: [])
        let viewModel = SetupViewModel(
            projectID: UUID(),
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: repository),
            updateSetupUseCase: UpdateSetupUseCase(projectRepository: repository)
        )

        XCTAssertFalse(viewModel.projectNotFound)
        await viewModel.load()

        XCTAssertTrue(viewModel.projectNotFound)
    }

    func test_load_projectExists_neverSetsProjectNotFound() async {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        await viewModel.load()

        XCTAssertFalse(viewModel.projectNotFound)
    }

    func test_load_projectDeletedAfterFirstLoad_thenLoadedAgain_setsProjectNotFound() async {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.load()
        XCTAssertFalse(viewModel.projectNotFound)

        try? await repository.delete(id: project.id)
        await viewModel.load()

        XCTAssertTrue(viewModel.projectNotFound)
    }

    // MARK: - Save timing

    func test_updateDebounced_savesAfterTheDelay_notImmediately() async throws {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        viewModel.updateDebounced(makeSetup(title: "New Title"))

        // Not yet saved — the debounce hasn't elapsed.
        let tooSoon = try await repository.fetch(id: project.id)
        XCTAssertEqual(tooSoon?.setup.title, "A Swiss Story")

        try await Task.sleep(nanoseconds: 60_000_000)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.setup.title, "New Title")
    }

    func test_updateDebounced_calledRepeatedly_onlySavesOnce_withTheLatestValue() async throws {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        viewModel.updateDebounced(makeSetup(title: "First"))
        viewModel.updateDebounced(makeSetup(title: "Second"))
        viewModel.updateDebounced(makeSetup(title: "Third"))
        try await Task.sleep(nanoseconds: 60_000_000)

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.setup.title, "Third")
    }

    func test_updateImmediately_savesRightAway_withNoDelay() async throws {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository, debounceNanoseconds: 5_000_000_000)

        await viewModel.updateImmediately(makeSetup(title: "New Title"))

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.setup.title, "New Title")
    }

    func test_flushPendingSave_withAPendingDebouncedEdit_savesImmediately() async throws {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository, debounceNanoseconds: 5_000_000_000)

        viewModel.updateDebounced(makeSetup(title: "New Title"))
        await viewModel.flushPendingSave()

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.setup.title, "New Title")
    }

    func test_flushPendingSave_withNothingPending_doesNotResaveOrBumpUpdatedAt() async throws {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)

        await viewModel.flushPendingSave()

        let persisted = try await repository.fetch(id: project.id)
        XCTAssertEqual(persisted?.updatedAt, project.updatedAt)
    }

    // MARK: - missingRequiredFields

    func test_missingRequiredFields_reflectsTheCurrentWorkingCopy() async {
        let project = makeProject(setup: makeSetup())
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.load()
        XCTAssertTrue(viewModel.missingRequiredFields.isEmpty)

        viewModel.updateDebounced(
            Setup(
                title: "",
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .notKnown,
                productionTypes: [.documentaryFilm],
                declarationDate: Date(timeIntervalSince1970: 0)
            )
        )

        XCTAssertTrue(viewModel.missingRequiredFields.contains(.title))
        XCTAssertTrue(viewModel.missingRequiredFields.contains(.producer))
    }

    /// Reversal: `SetupViewModel.missingRequiredFields` used to filter
    /// `.productionRuntime` out while this screen had no input for it (moved
    /// to Review & Export, D11, not built yet). `productionRuntime` ("Length
    /// of Film / Production") was re-added to this screen, so the filter's
    /// own premise no longer holds — this proves the reversal, not the
    /// original exclusion. See `docs/DECISIONS.md`.
    func test_missingRequiredFields_includesProductionRuntime_nowThatThisScreenHasAnInputForIt() async {
        let setup = Setup(
            title: "A Swiss Story",
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(setup.missingRequiredFields.contains(.productionRuntime))

        let project = makeProject(setup: setup)
        let repository = InMemoryProjectRepository(projects: [project])
        let viewModel = makeViewModel(project: project, repository: repository)
        await viewModel.load()

        XCTAssertTrue(viewModel.missingRequiredFields.contains(.productionRuntime))
    }

    // MARK: - Errors

    func test_saveFailure_setsErrorMessage() async {
        let project = makeProject(setup: makeSetup())
        // An empty repository — the Project doesn't exist there, so
        // UpdateSetupUseCase throws ProjectNotFoundError.
        let repository = InMemoryProjectRepository()
        let viewModel = makeViewModel(project: project, repository: repository, debounceNanoseconds: 5_000_000_000)

        await viewModel.updateImmediately(makeSetup(title: "New Title"))

        XCTAssertNotNil(viewModel.errorMessage)
    }
}
