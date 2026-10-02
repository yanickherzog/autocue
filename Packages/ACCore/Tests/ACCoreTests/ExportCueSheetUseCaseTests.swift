@testable import ACCore
import XCTest

/// Covers `ExportCueSheetUseCase.isExportAllowed` — the pure half, exercised
/// mock-free per `CONTRIBUTING.md` §5. The repository-touching `export(
/// projectID:...)` orchestration is exercised in `ACTestSupportTests` against
/// the real `InMemoryProjectRepository`/`InMemoryExportRepository` fakes, the
/// same split `CreateProjectUseCaseTests`/`ProjectLibraryUseCaseOrchestrationTests`
/// already establish.
final class ExportCueSheetUseCaseTests: XCTestCase {
    func test_isExportAllowed_noIssues_allowedRegardlessOfStrictness() {
        XCTAssertTrue(ExportCueSheetUseCase.isExportAllowed(issues: [], strictness: .warnOnly))
        XCTAssertTrue(ExportCueSheetUseCase.isExportAllowed(issues: [], strictness: .blockExport))
    }

    func test_isExportAllowed_issuesPresent_warnOnly_stillAllowed() {
        let issues: [CueSheetValidationIssue] = [.missingOtherProductionTypeDescription]
        XCTAssertTrue(ExportCueSheetUseCase.isExportAllowed(issues: issues, strictness: .warnOnly))
    }

    func test_isExportAllowed_issuesPresent_blockExport_notAllowed() {
        let issues: [CueSheetValidationIssue] = [.missingOtherProductionTypeDescription]
        XCTAssertFalse(ExportCueSheetUseCase.isExportAllowed(issues: issues, strictness: .blockExport))
    }
}
