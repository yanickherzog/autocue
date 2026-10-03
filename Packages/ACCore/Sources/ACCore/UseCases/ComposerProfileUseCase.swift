import Foundation

/// Thin wrapper around `ComposerProfileRepository` — mirrors
/// `WAFormTemplateUseCase`'s own shape exactly (`CLAUDE.md`'s Dependency
/// Injection Pattern: ViewModels call a Use Case, never a Repository
/// directly).
///
/// **The one piece of real logic this Use Case adds over a plain pass-
/// through:** `saveProfile` rejects an invalid IPI number before it ever
/// reaches storage, via `IPINumber.isValid`. This is deliberately enforced
/// here, not only in `ComposerProfileSetupViewModel`'s own `canSave` gate —
/// a ViewModel's `canSave` only controls whether its own Save *button* is
/// enabled; it is not a structural guarantee against a bad value entering
/// the one stored profile every future "That's Me" auto-fill reads from.
/// Business rules live in Use Cases, not ViewModels (`CLAUDE.md`, MVVM
/// section) — this is exactly that rule applied to the one real invariant
/// this feature has.
public struct ComposerProfileUseCase: Sendable {
    public enum SaveError: Error, Equatable {
        case invalidIPINumber
    }

    private let composerProfileRepository: ComposerProfileRepository

    public init(composerProfileRepository: ComposerProfileRepository) {
        self.composerProfileRepository = composerProfileRepository
    }

    public func currentProfile() -> ComposerProfile? {
        composerProfileRepository.currentProfile()
    }

    public func saveProfile(_ profile: ComposerProfile) throws {
        guard IPINumber.isValid(profile.ipiNumber) else {
            throw SaveError.invalidIPINumber
        }
        try composerProfileRepository.saveProfile(profile)
    }
}
