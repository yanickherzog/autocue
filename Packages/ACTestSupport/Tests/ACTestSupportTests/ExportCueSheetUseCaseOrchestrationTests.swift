import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `ExportCueSheetUseCase`'s repository-touching orchestration half
/// (`export(projectID:...)`) against the real `InMemoryProjectRepository`/
/// `InMemoryExportRepository` fakes — the pure `isExportAllowed` half is
/// already fully covered, mock-free, in `ACCoreTests` (`CONTRIBUTING.md` §5);
/// this proves the fakes actually work correctly with the real Use Case
/// end-to-end, the same split `DeleteRightHolderOrchestrationTests` already
/// establishes.
final class ExportCueSheetUseCaseOrchestrationTests: XCTestCase {
    private static func makeProject(
        id: UUID = UUID(),
        otherProductionTypeDescription: String? = "A real description"
    ) -> Project {
        Project(
            id: id,
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
                productionTypes: [.other],
                otherProductionTypeDescription: otherProductionTypeDescription,
                declarant: .person(UUID()),
                declarationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

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

    func test_export_validProject_succeeds() async {
        let project = Self.makeProject()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let exportedURL = URL(fileURLWithPath: "/tmp/reel-one.pdf")
        let exportRepository = InMemoryExportRepository(exportedURL: exportedURL)
        let useCase = ExportCueSheetUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: project.id, format: .pdf, to: exportedURL, shareValidationStrictness: .blockExport
        ))

        XCTAssertEqual(result.completed, exportedURL)
        XCTAssertNil(result.error)
    }

    func test_export_issuesPresent_blockExport_throwsWithoutCallingExportRepository() async {
        let project = Self.makeProject(otherProductionTypeDescription: nil)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let exportRepository = InMemoryExportRepository()
        let useCase = ExportCueSheetUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: project.id,
            format: .pdf,
            to: URL(fileURLWithPath: "/tmp/reel-one.pdf"),
            shareValidationStrictness: .blockExport
        ))

        XCTAssertNil(result.completed)
        guard case let ExportCueSheetUseCase.Failure.validationIssuesPresent(issues)? = result.error else {
            return XCTFail("Expected .validationIssuesPresent, got \(String(describing: result.error))")
        }
        XCTAssertEqual(issues, [.missingOtherProductionTypeDescription])
    }

    func test_export_issuesPresent_warnOnly_stillSucceeds() async {
        let project = Self.makeProject(otherProductionTypeDescription: nil)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let exportedURL = URL(fileURLWithPath: "/tmp/reel-one.xlsx")
        let exportRepository = InMemoryExportRepository(exportedURL: exportedURL)
        let useCase = ExportCueSheetUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: project.id, format: .xlsx, to: exportedURL, shareValidationStrictness: .warnOnly
        ))

        XCTAssertEqual(result.completed, exportedURL)
        XCTAssertNil(result.error)
    }

    func test_export_projectNotFound_throwsProjectNotFoundError() async {
        let missingID = UUID()
        let projectRepository = InMemoryProjectRepository(projects: [])
        let exportRepository = InMemoryExportRepository()
        let useCase = ExportCueSheetUseCase(projectRepository: projectRepository, exportRepository: exportRepository)

        let result = await collectResults(useCase.export(
            projectID: missingID,
            format: .pdf,
            to: URL(fileURLWithPath: "/tmp/reel-one.pdf"),
            shareValidationStrictness: .warnOnly
        ))

        XCTAssertEqual(result.error as? ProjectNotFoundError, ProjectNotFoundError(projectID: missingID))
    }
}
