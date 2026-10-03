import ACCore
import ACDesignSystem
import SwiftUI

/// Shown immediately after a `Person` with no address on file is selected
/// for a role that requires one (Declarant, Director — see
/// `PartyPickerView.promptsForMissingAddressOnSelect`) — the real fix for
/// the "WA Form export needs a complete address, but nothing ever prompted
/// for one" gap, replacing an earlier, more complicated role-gated design
/// (`docs/DECISIONS.md`, 2026-10-03). Selecting them already completed by
/// the time this sheet appears — this is a non-blocking follow-up, not a
/// gate on selection, hence "Skip."
///
/// Never shown for a `Person` who already has an address — `PartyPickerView`
/// only presents this when `address == nil` at selection time. Correcting
/// an *existing* address later is `PersonEditorSheet`'s own job (shown
/// automatically whenever `existing.address != nil`), not this sheet's —
/// this one only ever handles first-time capture.
struct PersonAddressPromptSheet: View {
    let person: Person
    /// "Declarant"/"Director" — names the role that triggered this prompt,
    /// purely for the copy below. Never stored on `Person` itself.
    let roleDescription: String
    let onSave: (Person) async -> SavePersonResult?
    let onSkip: () -> Void

    @State private var street = ""
    @State private var postalCode = ""
    @State private var city = ""
    @State private var country = ""
    @State private var isSaving = false

    private var currentAddress: PostalAddress {
        PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }

    /// Unlike `PersonEditorSheet`'s own address section (optional, an
    /// incomplete entry just means "no address"), this sheet's entire
    /// purpose is capturing one — so, like `LabelEditorSheet`, `Save` stays
    /// disabled until all four parts are present. Anyone who doesn't have
    /// the address on hand right now uses `Skip` instead, not a half-saved
    /// partial address.
    private var canSave: Bool {
        currentAddress.isComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Add Address")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)
            Text(
                "\(person.firstName) \(person.lastName) has no address on file yet. " +
                    "SUISA requires a complete address for the \(roleDescription)."
            )
            .font(Theme.Typography.font(.regular, size: 13))
            .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.7))

            PostalAddressFields(street: $street, postalCode: $postalCode, city: $city, country: $country)

            HStack {
                Spacer()
                Button("Skip", action: onSkip)
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                Button("Save", action: save)
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
                    .disabled(!canSave || isSaving)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
    }

    /// No duplicate-name handling, unlike `PersonEditorSheet`/`LabelEditorSheet`
    /// — `person`'s name is never touched here, only `address`, so
    /// `UpdateRightHolderDirectoryUseCase.savePerson`'s duplicate check
    /// (which compares against *other* directory entries) can't fire against
    /// this person's own unchanged name.
    private func save() {
        let updated = Person(
            id: person.id,
            firstName: person.firstName,
            lastName: person.lastName,
            ipiNumber: person.ipiNumber,
            address: currentAddress,
            email: person.email,
            swissPerformNumber: person.swissPerformNumber,
            intendedRoles: person.intendedRoles
        )
        isSaving = true
        Task {
            _ = await onSave(updated)
            isSaving = false
        }
    }
}
