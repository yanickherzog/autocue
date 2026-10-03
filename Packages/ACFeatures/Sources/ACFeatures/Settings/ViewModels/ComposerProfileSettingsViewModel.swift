import ACCore
import Foundation

/// Backs the `Settings` scene's "My Composer Profile" screen — the app
/// owner's own stored identity (`ComposerProfile`), used to auto-fill
/// "That's Me" (`PartyPickerView`). Built narrowly ahead of `ROADMAP.md`
/// D15's own full `SettingsViewModel`/`SettingsView` scope — see
/// `docs/DECISIONS.md`. Calls a Use Case only, per `CONTRIBUTING.md` §6.
@Observable
@MainActor
public final class ComposerProfileSettingsViewModel {
    public var firstName = ""
    public var lastName = ""
    public var ipiNumber = ""
    public var street = ""
    public var postalCode = ""
    public var city = ""
    public var country = ""
    public var email = ""
    public var swissPerformNumber = ""

    /// `true` until the very first successful save — gates the
    /// confirmation step below. Once a profile exists, further edits save
    /// directly: the "make editing simple, clearly worded for future edits
    /// only" requirement this feature was built against. Not `private` for
    /// `ComposerProfileSettingsView`'s own confirmation-vs-direct-save
    /// button wording.
    public private(set) var isFirstSave: Bool
    /// Set by `requestSave()` on the very first save, instead of persisting
    /// immediately — the View presents an alert showing
    /// `groupedIPIForConfirmation` and calls `confirmSave()`/
    /// `cancelConfirmation()` from its two actions. This is the one real
    /// safeguard this feature was built around: once persisted, this exact
    /// number silently propagates into every future "That's Me" auto-fill,
    /// so the user sees it back, clearly formatted, before that happens —
    /// not just whatever raw digits they typed.
    public var isShowingConfirmation = false
    public var errorMessage: String?
    public var didJustSave = false

    private let composerProfileUseCase: ComposerProfileUseCase

    public init(composerProfileUseCase: ComposerProfileUseCase) {
        self.composerProfileUseCase = composerProfileUseCase
        let existing = composerProfileUseCase.currentProfile()
        isFirstSave = existing == nil
        guard let existing else { return }
        firstName = existing.firstName
        lastName = existing.lastName
        ipiNumber = existing.ipiNumber
        street = existing.address?.street ?? ""
        postalCode = existing.address?.postalCode ?? ""
        city = existing.address?.city ?? ""
        country = existing.address?.country ?? ""
        email = existing.email ?? ""
        swissPerformNumber = existing.swissPerformNumber ?? ""
    }

    private var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLastName: String { lastName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Gates the Save button. The real IPI structure check
    /// (`IPINumber.isValid`) — not just "non-empty" — is deliberately
    /// enforced here too, not only inside `ComposerProfileUseCase.saveProfile`:
    /// this is what the user actually sees disabled while typing an
    /// incomplete/malformed number, before any save attempt happens at all.
    public var canSave: Bool {
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty && IPINumber.isValid(ipiNumber)
    }

    public var groupedIPIForConfirmation: String {
        IPINumber.grouped(ipiNumber)
    }

    private var currentAddress: PostalAddress {
        PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }

    public func requestSave() {
        guard canSave else { return }
        if isFirstSave {
            isShowingConfirmation = true
        } else {
            persist()
        }
    }

    public func confirmSave() {
        isShowingConfirmation = false
        persist()
    }

    public func cancelConfirmation() {
        isShowingConfirmation = false
    }

    private func persist() {
        let profile = ComposerProfile(
            firstName: trimmedFirstName,
            lastName: trimmedLastName,
            ipiNumber: ipiNumber,
            address: currentAddress.isComplete ? currentAddress : nil,
            email: email.isEmpty ? nil : email,
            swissPerformNumber: swissPerformNumber.isEmpty ? nil : swissPerformNumber
        )
        do {
            try composerProfileUseCase.saveProfile(profile)
            isFirstSave = false
            didJustSave = true
        } catch {
            errorMessage = "Couldn't save your profile: \(error.localizedDescription)"
        }
    }
}
