import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `WAFormTemplateUseCase`, `ComputeWAFormLayoutUseCase`, and
/// `ExportWAFormUseCase` (`ROADMAP.md` D12) against the real
/// `InMemoryWAFormTemplateRepository`/`InMemoryExportRepository`/
/// `InMemoryProjectRepository` fakes — the same "prove the fakes actually
/// work correctly with the real Use Case end-to-end" shape
/// `ExportCueSheetUseCaseOrchestrationTests` already establishes. None of
/// these three Use Cases has a pure half worth isolating in `ACCoreTests`
/// (unlike `ExportCueSheetUseCase.isExportAllowed`) — each is pure
/// orchestration over a Repository protocol.
final class WAFormUseCaseOrchestrationTests: XCTestCase {
    // MARK: - WAFormTemplateUseCase

    func test_waFormTemplateUseCase_currentTemplate_nilWhenNoneImported() {
        let repository = InMemoryWAFormTemplateRepository()
        let useCase = WAFormTemplateUseCase(waFormTemplateRepository: repository)
        XCTAssertNil(useCase.currentTemplate())
    }

    func test_waFormTemplateUseCase_importTemplate_delegatesAndReturnsTheRealReference() throws {
        let repository = InMemoryWAFormTemplateRepository()
        let useCase = WAFormTemplateUseCase(waFormTemplateRepository: repository)

        let reference = try useCase.importTemplate(
            mainFormURL: URL(fileURLWithPath: "/tmp/main.pdf"),
            continuationFormURL: URL(fileURLWithPath: "/tmp/continuation.pdf")
        )

        XCTAssertEqual(useCase.currentTemplate(), reference)
        XCTAssertEqual(reference.mainFormFileName, "main.pdf")
    }

    func test_waFormTemplateUseCase_importTemplate_propagatesARealError() {
        enum TestError: Error { case boom }
        let repository = InMemoryWAFormTemplateRepository(importError: TestError.boom)
        let useCase = WAFormTemplateUseCase(waFormTemplateRepository: repository)

        XCTAssertThrowsError(try useCase.importTemplate(
            mainFormURL: URL(fileURLWithPath: "/tmp/main.pdf"),
            continuationFormURL: URL(fileURLWithPath: "/tmp/continuation.pdf")
        ))
    }

    func test_waFormTemplateUseCase_templateFileURLs_nilWhenNoneImported() {
        let repository = InMemoryWAFormTemplateRepository()
        let useCase = WAFormTemplateUseCase(waFormTemplateRepository: repository)
        XCTAssertNil(useCase.templateFileURLs())
    }

    func test_waFormTemplateUseCase_templateFileURLs_nonNilOnceImported() throws {
        let repository = InMemoryWAFormTemplateRepository()
        let useCase = WAFormTemplateUseCase(waFormTemplateRepository: repository)
        _ = try useCase.importTemplate(
            mainFormURL: URL(fileURLWithPath: "/tmp/main.pdf"),
            continuationFormURL: URL(fileURLWithPath: "/tmp/continuation.pdf")
        )

        XCTAssertNotNil(useCase.templateFileURLs())
    }

    // MARK: - ComputeWAFormLayoutUseCase

    func test_computeWAFormLayoutUseCase_delegatesToExportRepository() throws {
        let fakeLayout = [CueSheetPageLayout(pageIndex: 0, pageCount: 1, elements: [])]
        let exportRepository = InMemoryExportRepository(waFormLayoutToReturn: fakeLayout)
        let useCase = ComputeWAFormLayoutUseCase(exportRepository: exportRepository)

        let result = try useCase.compute(for: ProjectFixture.make())

        XCTAssertEqual(result, fakeLayout)
    }

    func test_computeWAFormLayoutUseCase_propagatesARealError() {
        enum TestError: Error { case boom }
        let exportRepository = InMemoryExportRepository(waFormLayoutError: TestError.boom)
        let useCase = ComputeWAFormLayoutUseCase(exportRepository: exportRepository)

        XCTAssertThrowsError(try useCase.compute(for: ProjectFixture.make()))
    }

    // MARK: - ExportWAFormUseCase

    private func collectResults(
        _ stream: AsyncThrowingStream<OperationProgress<URL>, Error>
    ) async -> (completed: URL?, error: Error?) {
        do {
            var completed: URL?
            for try await progress in stream {
                if case let .completed(url) = progress {
                    completed = url
                }
            }
            return (completed, nil)
        } catch {
            return (nil, error)
        }
    }

    func test_exportWAFormUseCase_validProject_succeeds() async {
        let project = ProjectFixture.make()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let destination = URL(fileURLWithPath: "/tmp/wa-film.pdf")
        let exportRepository = InMemoryExportRepository(exportedURL: destination)
        let useCase = ExportWAFormUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: project.id,
            to: destination,
            shareValidationStrictness: .warnOnly
        ))

        XCTAssertEqual(result.completed, destination)
        XCTAssertNil(result.error)
    }

    func test_exportWAFormUseCase_projectNotFound_throwsProjectNotFoundError() async {
        let missingID = UUID()
        let projectRepository = InMemoryProjectRepository(projects: [])
        let exportRepository = InMemoryExportRepository()
        let useCase = ExportWAFormUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: missingID,
            to: URL(fileURLWithPath: "/tmp/wa-film.pdf"),
            shareValidationStrictness: .warnOnly
        ))

        XCTAssertEqual(result.error as? ProjectNotFoundError, ProjectNotFoundError(projectID: missingID))
    }

    /// A minimal fixture with one deliberate, real issue (a `Cue` with no
    /// right-holders — `CueSheetValidationIssue.cueHasNoRightHolders`,
    /// surfaced here via `WAFormValidationIssue.cueSheetIssue(_:)`) rather
    /// than `ProjectFixture.makeMinimal()`, which is deliberately
    /// fully-valid per its own doc comment and so can't exercise the
    /// blocking path at all.
    private func makeProjectWithOneIssue() -> Project {
        let base = ProjectFixture.makeMinimal()
        let cueWithNoRightHolders = Cue(
            title: "Untitled Cue",
            duration: MediaDuration(seconds: 30),
            rightHolders: [],
            source: .manual
        )
        return Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: [cueWithNoRightHolders]
        )
    }

    func test_exportWAFormUseCase_blockExportStrictness_withIssues_throwsValidationIssuesPresent() async {
        let project = makeProjectWithOneIssue()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let exportRepository = InMemoryExportRepository()
        let useCase = ExportWAFormUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: project.id,
            to: URL(fileURLWithPath: "/tmp/wa-film.pdf"),
            shareValidationStrictness: .blockExport
        ))

        guard case let .validationIssuesPresent(issues)? = result.error as? ExportWAFormUseCase.Failure else {
            XCTFail("Expected .validationIssuesPresent, got \(String(describing: result.error))")
            return
        }
        XCTAssertEqual(issues, [WAFormValidationIssue.cueSheetIssue(.cueHasNoRightHolders(cueID: project.cues[0].id))])
    }

    func test_exportWAFormUseCase_warnOnlyStrictness_withIssues_stillExports() async {
        let project = makeProjectWithOneIssue()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let destination = URL(fileURLWithPath: "/tmp/wa-film.pdf")
        let exportRepository = InMemoryExportRepository(exportedURL: destination)
        let useCase = ExportWAFormUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: project.id,
            to: destination,
            shareValidationStrictness: .warnOnly
        ))

        XCTAssertEqual(result.completed, destination)
        XCTAssertNil(result.error)
    }
}
