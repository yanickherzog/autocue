import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `ComposerProfileUseCase` against the real
/// `InMemoryComposerProfileRepository` fake — same "prove the fake actually
/// works correctly with the real Use Case end-to-end" shape
/// `WAFormUseCaseOrchestrationTests` already establishes. Real,
/// independently-sourced valid IPI numbers throughout (confirmed via
/// `IPINumberTests`, `ACCoreTests`) — not the unvalidated placeholder
/// numbers used elsewhere in this codebase's ordinary `Person` fixtures.
final class ComposerProfileUseCaseTests: XCTestCase {
    private func makeProfile(ipiNumber: String = "01234567846") -> ComposerProfile {
        ComposerProfile(firstName: "Ada", lastName: "Lovelace", ipiNumber: ipiNumber)
    }

    func test_currentProfile_nilWhenNeverSaved() {
        let repository = InMemoryComposerProfileRepository()
        let useCase = ComposerProfileUseCase(composerProfileRepository: repository)
        XCTAssertNil(useCase.currentProfile())
    }

    func test_saveProfile_validIPI_persistsAndIsReadableBack() throws {
        let repository = InMemoryComposerProfileRepository()
        let useCase = ComposerProfileUseCase(composerProfileRepository: repository)
        let profile = makeProfile()

        try useCase.saveProfile(profile)

        XCTAssertEqual(useCase.currentProfile(), profile)
    }

    /// The one real invariant this Use Case adds over a plain pass-through
    /// — see its own doc comment: a bad IPI number must never reach
    /// storage, even if some future caller's own `canSave`-style UI gate
    /// has a bug.
    func test_saveProfile_invalidIPI_throwsAndNeverReachesStorage() {
        let repository = InMemoryComposerProfileRepository()
        let useCase = ComposerProfileUseCase(composerProfileRepository: repository)
        let invalid = makeProfile(ipiNumber: "00000000001")

        XCTAssertThrowsError(try useCase.saveProfile(invalid)) { error in
            XCTAssertEqual(error as? ComposerProfileUseCase.SaveError, .invalidIPINumber)
        }
        XCTAssertNil(repository.storedProfile)
    }

    func test_saveProfile_propagatesARealRepositoryError() {
        enum TestError: Error { case boom }
        let repository = InMemoryComposerProfileRepository(saveError: TestError.boom)
        let useCase = ComposerProfileUseCase(composerProfileRepository: repository)

        XCTAssertThrowsError(try useCase.saveProfile(makeProfile()))
    }

    func test_saveProfile_replacesAPreviouslyStoredProfileEntirely() throws {
        let repository = InMemoryComposerProfileRepository()
        let useCase = ComposerProfileUseCase(composerProfileRepository: repository)
        try useCase.saveProfile(makeProfile())

        let replacement = ComposerProfile(firstName: "Grace", lastName: "Hopper", ipiNumber: "00123456790")
        try useCase.saveProfile(replacement)

        XCTAssertEqual(useCase.currentProfile(), replacement)
    }
}
