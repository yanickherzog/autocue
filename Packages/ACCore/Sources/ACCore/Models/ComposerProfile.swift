import Foundation

/// The app owner's own composer/right-holder identity — name, IPI number,
/// and address — stored once, app-level (not per-`Project`), so it can be
/// reused to auto-fill a new `Person` entry anywhere this same individual
/// is added as a right-holder, via "That's Me" (`PartyPickerView`).
///
/// **Deliberately narrow — this is not a general cross-project
/// name-matching system.** A broader "has this exact person already been
/// entered somewhere else" lookup would risk a false match between two
/// different people who happen to share a name, which is a real concern on
/// a document carrying financial/legal weight (SUISA's declaration). This
/// type only ever represents *this app's own user*, confirmed explicitly by
/// them at save time (`ComposerProfileSetupView`'s confirmation step) —
/// never inferred.
///
/// No `id` field and no `Identifiable` conformance — there is exactly one
/// of these, app-wide, the same "no natural identity concept" shape as
/// `Settings` (`CLAUDE.md`, "Domain Model Value-Type Conformances").
/// `Sendable`/`Equatable` for the same reasons established there; no
/// `Codable` — `ComposerProfileRepositoryImpl` round-trips individual
/// `UserDefaults` keys per field, the same pattern `WAFormTemplateReference`
/// already established, so there is no real serialization use case to
/// justify it (`CLAUDE.md` rule 16).
public struct ComposerProfile: Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    /// Always the full, real IPI Name Number structure — 11 digits, the
    /// last 2 being real check digits — validated via `IPINumber.isValid`
    /// before this profile is ever saved (`ComposerProfileSetupViewModel`).
    /// Unlike `Person.ipiNumber` (an optional, unvalidated free-text field —
    /// SPEC.md §4.5), a stored `ComposerProfile` never holds an unvalidated
    /// or partial value: the whole point of validating once, carefully, at
    /// profile-save time is to avoid silently propagating a wrong number
    /// into every right-holder entry it later auto-fills.
    public var ipiNumber: String
    public var address: PostalAddress?
    public var email: String?
    public var swissPerformNumber: String?

    public init(
        firstName: String,
        lastName: String,
        ipiNumber: String,
        address: PostalAddress? = nil,
        email: String? = nil,
        swissPerformNumber: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.ipiNumber = ipiNumber
        self.address = address
        self.email = email
        self.swissPerformNumber = swissPerformNumber
    }
}
