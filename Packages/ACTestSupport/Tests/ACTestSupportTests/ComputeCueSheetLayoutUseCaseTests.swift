import ACCore
@testable import ACTestSupport
import XCTest

/// `ComputeCueSheetLayoutUseCase` (`ROADMAP.md` D11/T11.2) against
/// `InMemoryExportRepository` — lives here, not `ACCoreTests`, since it
/// needs a fake `ExportRepository` and `ACTestSupport` can't be a dependency
/// of `ACCore`'s own test target without a package cycle (the same reason
/// `DeleteRightHolderOrchestrationTests` lives here rather than in
/// `ACCoreTests`).
final class ComputeCueSheetLayoutUseCaseTests: XCTestCase {
    func test_compute_delegatesToTheRepository() {
        let expectedLayout = [CueSheetPageLayout(pageIndex: 0, pageCount: 1, elements: [])]
        let repository = InMemoryExportRepository(layoutToReturn: expectedLayout)
        let useCase = ComputeCueSheetLayoutUseCase(exportRepository: repository)

        let result = useCase.compute(for: ProjectFixture.make())

        XCTAssertEqual(result, expectedLayout)
    }

    func test_compute_emptyRepositoryResult_returnsEmpty() {
        let repository = InMemoryExportRepository(layoutToReturn: [])
        let useCase = ComputeCueSheetLayoutUseCase(exportRepository: repository)

        XCTAssertEqual(useCase.compute(for: ProjectFixture.make()), [])
    }
}
