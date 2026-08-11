import ACCore
import ACDesignSystem
import SwiftUI

/// Create/edit sheet for one `Person` (SPEC.md §4.5) — the same sheet for
/// both flows, distinguished by whether `existing` is set (`ROADMAP.md`
/// D7/T7.3). Receives `onSave`/`onCancel` as plain closures, not a
/// `RightHolderDirectoryViewModel` reference directly — the same
/// adapter-at-the-edge pattern `ProjectLibraryView`'s `NewProjectSheet`
/// already establishes; the caller (`SetupView`) wires `onSave` to the
/// ViewModel.
///
/// **No address field by default.** `Person.address` is optional generally
/// (SPEC.md §4.5) — required only when a `Person` is used as
/// `Setup.producer`/`.directorOrPrincipal`/`.declarant`, unlike `Label`,
/// whose address is always required. Prompting for it on every ordinary
/// collaborator (a composer, an arranger) doesn't match that, so this sheet
/// leaves `address` untouched by default, never showing UI for it — except
/// when `showsAddressField` is explicitly set (see that property's own doc
/// comment). On an *edit* of an existing `Person` that already has an
/// address (e.g. one previously used as a producer), `save()` preserves
/// `existing?.address` unchanged whenever this sheet doesn't show the
/// field — it just never offers to *set* one outside that one flow.
struct PersonEditorSheet: View {
    let existing: Person?
    /// Pre-fills `Person.intendedRoles` (as a single-element set) when
    /// creating a new `Person` from one of the Setup screen's
    /// collaborator-roster buckets' "Select" pickers (`ROADMAP.md` D7) —
    /// ignored when `existing != nil`, since editing preserves whatever
    /// role(s) the person already holds rather than resetting to just this
    /// one. No UI control for this field in this sheet: it's set entirely by
    /// which roster bucket's picker was opened, not something this form
    /// exposes for reassignment. A `Person` can hold more than one role
    /// simultaneously (`Person.intendedRoles`' own doc comment) — this only
    /// ever suggests the *one* role relevant to whichever picker created
    /// them; adding a second role later happens by selecting them again from
    /// a different bucket's picker, not by editing here.
    let initialIntendedRole: PersonIntendedRole?
    /// Hides the "IPI Number (optional)" field entirely when `false` — IPI
    /// numbers are a CISAC identifier relevant to SUISA-registered
    /// musicians, not to companies or directors, so Producer*in/Regisseur*in's
    /// own "+ New Artist" creation flow (`PartyPickerView`, reached via
    /// `MultiPartyFieldBucket`) passes `false` here. **Creation-only, never
    /// edit:** every other `PersonEditorSheet` instantiation — every edit
    /// sheet, reached however (a roster row's name, a picker's pencil icon,
    /// Producer*in/Regisseur*in's own row) — keeps the default `true`, so
    /// IPI-Nr is always shown/editable for an existing `Person` regardless
    /// of which context first created them or which bucket they're
    /// currently viewed from. This is a transient "which sheet instance"
    /// flag, never a stored property on `Person` itself — a person created
    /// via Producer*in and later also added to Komponist*in still shows
    /// IPI-Nr correctly the moment their entry is opened for editing from
    /// anywhere. See `docs/DECISIONS.md`.
    let showsIPINumberField: Bool
    /// Shows `PostalAddressFields` when `true` — `false` (default) preserves
    /// this sheet's original "no address UI" behavior everywhere except one
    /// specific context: Regisseur*in's own "+ New Artist" creation flow
    /// (`MultiPartyFieldBucket`/`PartyPickerView`, `scope: .personOnly`).
    /// SUISA's real WA Film form requires a "complete address" for both
    /// Producer and Director ("Produzent (vollständige Adresse)"/"Regisseur
    /// ... (vollständige Adresse)") — Producer*in already satisfies this in
    /// practice, since a Producer is almost always a `Label` (production
    /// company), and `Label.address` is already always-required via the
    /// existing "+ New Company" flow. Regisseur*in is `Person`-only (no
    /// Company option, per SPEC.md §4.5 — a director is always a person),
    /// and `Person`'s creation form had no address UI at all until this
    /// property — so it was the one genuine gap. **Known, accepted residual
    /// gap, not fixed here:** if a Producer is ever an individual `Person`
    /// rather than a company, there's still no way to capture their
    /// address, since this flag applies only to Regisseur*in's picker.
    /// Acceptable since a Producer is almost always a company in practice —
    /// revisit only if a real need for an individual-person Producer's
    /// address surfaces. **Creation-only, never edit** — same reasoning as
    /// `showsIPINumberField`: every edit sheet (however reached) keeps the
    /// default `false` and simply preserves `existing?.address` unchanged,
    /// so this never risks silently clearing an address a `Person` already
    /// has when they're edited from a context that doesn't show this field.
    let showsAddressField: Bool
    /// `async`, returning the Use Case's `SavePersonResult` (post-D7
    /// click-through-fix round) rather than a fire-and-forget `Void` — this
    /// sheet needs to know whether the save actually succeeded so it can
    /// stay open and show an inline message on `.duplicateName`, instead of
    /// dismissing unconditionally and letting the caller silently create a
    /// duplicate `Person`. `nil` means the save call itself failed (e.g. the
    /// `Project` no longer exists) — treated the same as a duplicate for UI
    /// purposes: stay open, `errorMessage` on `RightHolderDirectoryViewModel`
    /// already surfaces the real cause elsewhere.
    let onSave: (Person) async -> SavePersonResult?
    let onCancel: () -> Void

    @State private var firstName: String
    @State private var lastName: String
    @State private var ipiNumber: String
    @State private var email: String
    /// No UI field for this — hidden from the form (`ROADMAP.md` D7, later
    /// round), but still round-tripped: seeded from `existing` and written
    /// back unchanged in `save()`, so an edit never silently clears a value
    /// this sheet just doesn't offer a way to set or change.
    @State private var swissPerformNumber: String
    /// Only ever read/written when `showsAddressField` is `true` — see that
    /// property's doc comment. Seeded from `existing?.address` regardless
    /// (harmless when unused), the same pattern every other field here uses.
    @State private var street: String
    @State private var postalCode: String
    @State private var city: String
    @State private var country: String
    @State private var duplicateNameWarning: String?
    @State private var isSaving = false

    init(
        existing: Person?,
        initialIntendedRole: PersonIntendedRole? = nil,
        showsIPINumberField: Bool = true,
        showsAddressField: Bool = false,
        onSave: @escaping (Person) async -> SavePersonResult?,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.initialIntendedRole = initialIntendedRole
        self.showsIPINumberField = showsIPINumberField
        self.showsAddressField = showsAddressField
        self.onSave = onSave
        self.onCancel = onCancel
        _firstName = State(initialValue: existing?.firstName ?? "")
        _lastName = State(initialValue: existing?.lastName ?? "")
        _ipiNumber = State(initialValue: existing?.ipiNumber ?? "")
        _email = State(initialValue: existing?.email ?? "")
        _swissPerformNumber = State(initialValue: existing?.swissPerformNumber ?? "")
        let address = existing?.address
        _street = State(initialValue: address?.street ?? "")
        _postalCode = State(initialValue: address?.postalCode ?? "")
        _city = State(initialValue: address?.city ?? "")
        _country = State(initialValue: address?.country ?? "")
    }

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only assembled/consulted when `showsAddressField` is `true` — see
    /// `save()`. Unlike `LabelEditorSheet.currentAddress` (always required),
    /// an incomplete entry here simply means "no address," not a blocked
    /// save — `Person.address` is optional, so this sheet's `canSave` never
    /// depends on address completeness the way `LabelEditorSheet`'s does.
    private var currentAddress: PostalAddress {
        PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }

    private var canSave: Bool {
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(existing == nil ? "New Artist" : "Edit Artist")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            HStack(spacing: Theme.Spacing.sm) {
                GhostTextField(placeholder: "First Name", text: $firstName)
                GhostTextField(placeholder: "Last Name", text: $lastName)
            }
            if showsIPINumberField {
                GhostTextField(placeholder: "IPI Number (optional)", text: $ipiNumber)
            }
            GhostTextField(placeholder: "Email (optional)", text: $email)
            if showsAddressField {
                PostalAddressFields(street: $street, postalCode: $postalCode, city: $city, country: $country)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
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
        .errorAlert(message: $duplicateNameWarning)
    }

    private func save() {
        let intendedRoles: Set<PersonIntendedRole> = if let existing {
            existing.intendedRoles
        } else if let initialIntendedRole {
            [initialIntendedRole]
        } else {
            []
        }
        let person = Person(
            id: existing?.id ?? UUID(),
            firstName: trimmedFirstName,
            lastName: trimmedLastName,
            ipiNumber: ipiNumber.isEmpty ? nil : ipiNumber,
            address: showsAddressField ? (currentAddress.isComplete ? currentAddress : nil) : existing?.address,
            email: email.isEmpty ? nil : email,
            swissPerformNumber: swissPerformNumber.isEmpty ? nil : swissPerformNumber,
            intendedRoles: intendedRoles
        )
        isSaving = true
        Task {
            let result = await onSave(person)
            isSaving = false
            if case let .duplicateName(existingMatch) = result {
                duplicateNameWarning =
                    "\(existingMatch.firstName) \(existingMatch.lastName) is already in this project's directory. " +
                    "Use a different name, or select the existing entry instead of adding a duplicate."
            }
            // `.saved` and `nil` (the Use Case call itself failed —
            // `RightHolderDirectoryViewModel.errorMessage` surfaces that
            // separately) both dismiss; only a confirmed duplicate keeps
            // this sheet open.
        }
    }
}
