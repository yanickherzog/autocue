@testable import ACCore
import XCTest

/// Covers `CreateProjectUseCase.makeDefaultSetup` — the pure half, exercised
/// mock-free per `CONTRIBUTING.md` §5. The repository-touching `create(name:)`
/// orchestration is exercised in `ACTestSupportTests` against the real
/// `InMemoryProjectRepository` fake, the same split
/// `DeleteRightHolderUseCaseTests`/`DeleteRightHolderOrchestrationTests`
/// already establish.
final class CreateProjectUseCaseTests: XCTestCase {
    func test_makeDefaultSetup_usesTheGivenTitle() {
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(setup.title, "Reel One")
    }

    func test_makeDefaultSetup_leavesProducerDirectorDeclarantAtTheirOwnUnsetValue() {
        // A brand-new Project has no Person/Label in its directory yet to
        // reference — see docs/DECISIONS.md, "Setup's three Party fields
        // become optional." producer/directorOrPrincipal are [Party] (later
        // round) — empty array is their own unset value; declarant stays
        // Party?, using nil.
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(setup.producer.isEmpty)
        XCTAssertTrue(setup.directorOrPrincipal.isEmpty)
        XCTAssertNil(setup.declarant)
    }

    func test_makeDefaultSetup_productionYearIsZeroNotAGuessedCurrentYear() {
        // Deliberately 0, not Calendar-derived — a plausible-looking guessed
        // year would be exactly the silently-satisfying default this project
        // has already decided against. See docs/DECISIONS.md.
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: Date())
        XCTAssertEqual(setup.productionYear, 0)
    }

    func test_makeDefaultSetup_runtimesAreZero() {
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(setup.productionRuntime, .zero)
        XCTAssertEqual(setup.totalMusicRuntime, .zero)
    }

    func test_makeDefaultSetup_productionTypesIsEmpty() {
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(setup.productionTypes.isEmpty)
    }

    func test_makeDefaultSetup_containsAdditionalUndeclaredWorksIsNo() {
        // .no, not .notKnown — a deliberate default change; see
        // CreateProjectUseCase.makeDefaultSetup's own comment and
        // docs/DECISIONS.md.
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(setup.containsAdditionalUndeclaredWorks, .no)
    }

    func test_makeDefaultSetup_declarationDateIsTheGivenNow() {
        let now = Date(timeIntervalSince1970: 1_699_000_000)
        let setup = CreateProjectUseCase.makeDefaultSetup(title: "Reel One", now: now)
        XCTAssertEqual(setup.declarationDate, now)
    }
}
