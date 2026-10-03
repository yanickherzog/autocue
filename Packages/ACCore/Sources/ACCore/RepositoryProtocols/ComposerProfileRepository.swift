import Foundation

/// The Data-layer boundary for the app owner's own stored `ComposerProfile`
/// — implemented by `ACPersistence`'s `UserDefaults`-backed
/// `ComposerProfileRepositoryImpl`, mirroring `WAFormTemplateRepository`'s
/// own shape (narrow, single-value, reached through a proper `ACCore`
/// protocol rather than `ACFeatures` importing `Foundation.UserDefaults`
/// directly).
///
/// **Stored app-level, not routed through `Settings`/`SettingsRepository` —
/// same reasoning as `WAFormTemplateRepository`'s own doc comment.**
/// `Settings` has no `SettingsRepository` yet (`ROADMAP.md` D15/T15.1); this
/// is a small, independent store built ahead of that Deliverable, not a
/// piece of it — `RightHolderDirectoryViewModel`'s own doc comment already
/// warns against adding a `SettingsRepository`-*shaped* dependency ahead of
/// D15, which this deliberately isn't: it's a narrow, single-purpose
/// protocol for one unrelated value, not a general settings store.
///
/// `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless."
public protocol ComposerProfileRepository: Sendable {
    /// The currently-stored profile, or `nil` if the user has never saved
    /// one — the signal `PartyPickerView`'s "That's Me" button uses to
    /// decide whether to show itself at all.
    func currentProfile() -> ComposerProfile?

    /// Persists `profile`, replacing any previously-stored one in full —
    /// there is only ever one. Validation (IPI format, non-empty name) is
    /// the caller's responsibility (`ComposerProfileUseCase`/
    /// `ComposerProfileSetupViewModel`), not this repository's — it stores
    /// whatever it's given, the same "validation lives above the
    /// repository" discipline the rest of this codebase already follows.
    func saveProfile(_ profile: ComposerProfile) throws
}
