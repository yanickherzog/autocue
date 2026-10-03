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
    private func makeReference() -> WAFormTemplateReference {
        WAFormTemplateReference(
            mainFormBookmark: Data([1, 2, 3]),
            mainFormAccessMode: .securityScoped,
            mainFormFileName: "WA Film.pdf",
            continuationFormBookmark: Data([4, 5, 6]),
            continuationFormAccessMode: .securityScoped,
            continuationFormFileName: "WA Film II.pdf",
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

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

    // MARK: - ComputeWAFormLayoutUseCase

    func test_computeWAFormLayoutUseCase_delegatesToExportRepository() throws {
        let fakeLayout = [CueSheetPageLayout(pageIndex: 0, pageCount: 1, elements: [])]
        let exportRepository = InMemoryExportRepository(waFormLayoutToReturn: fakeLayout)
        let useCase = ComputeWAFormLayoutUseCase(exportRepository: exportRepository)

        let result = try useCase.compute(for: ProjectFixture.make(), template: makeReference())

        XCTAssertEqual(result, fakeLayout)
    }

    func test_computeWAFormLayoutUseCase_propagatesARealError() {
        enum TestError: Error { case boom }
        let exportRepository = InMemoryExportRepository(waFormLayoutError: TestError.boom)
        let useCase = ComputeWAFormLayoutUseCase(exportRepository: exportRepository)

        XCTAssertThrowsError(try useCase.compute(for: ProjectFixture.make(), template: makeReference()))
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
            template: makeReference(),
            to: destination
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
            template: makeReference(),
            to: URL(fileURLWithPath: "/tmp/wa-film.pdf")
        ))

        XCTAssertEqual(result.error as? ProjectNotFoundError, ProjectNotFoundError(projectID: missingID))
    }
}
