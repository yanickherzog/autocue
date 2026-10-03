import ACCore
@testable import ACFeatures
import ACTestSupport
import XCTest

@MainActor
final class ComposerProfileSettingsViewModelTests: XCTestCase {
    private func makeViewModel(
        storedProfile: ComposerProfile? = nil
    ) -> (ComposerProfileSettingsViewModel, InMemoryComposerProfileRepository) {
        let repository = InMemoryComposerProfileRepository(storedProfile: storedProfile)
        let viewModel = ComposerProfileSettingsViewModel(
            composerProfileUseCase: ComposerProfileUseCase(composerProfileRepository: repository)
        )
        return (viewModel, repository)
    }

    func test_init_noStoredProfile_formIsBlankAndIsFirstSaveIsTrue() {
        let (viewModel, _) = makeViewModel()

        XCTAssertTrue(viewModel.isFirstSave)
        XCTAssertEqual(viewModel.firstName, "")
        XCTAssertEqual(viewModel.ipiNumber, "")
    }

    func test_init_storedProfileExists_formIsPrefilledAndIsFirstSaveIsFalse() {
        let profile = ComposerProfile(firstName: "Ada", lastName: "Lovelace", ipiNumber: "01234567846")
        let (viewModel, _) = makeViewModel(storedProfile: profile)

        XCTAssertFalse(viewModel.isFirstSave)
        XCTAssertEqual(viewModel.firstName, "Ada")
        XCTAssertEqual(viewModel.lastName, "Lovelace")
        XCTAssertEqual(viewModel.ipiNumber, "01234567846")
    }

    func test_canSave_blankName_isFalseEvenWithAValidIPI() {
        let (viewModel, _) = makeViewModel()
        viewModel.ipiNumber = "01234567846"
        XCTAssertFalse(viewModel.canSave)
    }

    func test_canSave_malformedIPI_isFalseEvenWithANameFilledIn() {
        let (viewModel, _) = makeViewModel()
        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        viewModel.ipiNumber = "not-a-real-ipi"
        XCTAssertFalse(viewModel.canSave)
    }

    func test_canSave_nameAndValidIPI_isTrue() {
        let (viewModel, _) = makeViewModel()
        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        viewModel.ipiNumber = "01234567846"
        XCTAssertTrue(viewModel.canSave)
    }

    /// The feature's own explicit requirement: the very first save shows a
    /// confirmation step with the grouped IPI format before anything is
    /// actually persisted.
    func test_requestSave_firstSave_showsConfirmation_doesNotPersistYet() {
        let (viewModel, repository) = makeViewModel()
        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        viewModel.ipiNumber = "01234567846"

        viewModel.requestSave()

        XCTAssertTrue(viewModel.isShowingConfirmation)
        XCTAssertEqual(viewModel.groupedIPIForConfirmation, "01234 56 78 46")
        XCTAssertNil(repository.storedProfile)
    }

    func test_confirmSave_afterFirstSaveConfirmation_persistsAndClearsIsFirstSave() {
        let (viewModel, repository) = makeViewModel()
        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        viewModel.ipiNumber = "01234567846"
        viewModel.requestSave()

        viewModel.confirmSave()

        XCTAssertFalse(viewModel.isShowingConfirmation)
        XCTAssertFalse(viewModel.isFirstSave)
        XCTAssertEqual(repository.storedProfile?.firstName, "Ada")
        XCTAssertEqual(repository.storedProfile?.ipiNumber, "01234567846")
    }

    func test_cancelConfirmation_doesNotPersist() {
        let (viewModel, repository) = makeViewModel()
        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        viewModel.ipiNumber = "01234567846"
        viewModel.requestSave()

        viewModel.cancelConfirmation()

        XCTAssertFalse(viewModel.isShowingConfirmation)
        XCTAssertNil(repository.storedProfile)
    }

    /// Editing an already-saved profile is the "future only, simple
    /// editing" path — no confirmation gate the second time.
    func test_requestSave_profileAlreadyExists_savesDirectlyWithoutConfirmation() {
        let existing = ComposerProfile(firstName: "Ada", lastName: "Lovelace", ipiNumber: "01234567846")
        let (viewModel, repository) = makeViewModel(storedProfile: existing)
        viewModel.lastName = "Byron"

        viewModel.requestSave()

        XCTAssertFalse(viewModel.isShowingConfirmation)
        XCTAssertEqual(repository.storedProfile?.lastName, "Byron")
    }
}
