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
/// **Shows the address section if and only if `existing` already has an
/// address — never on creation, no external flag needed.** `Person.address`
/// is optional generally (SPEC.md §4.5) — prompting for it on every ordinary
/// collaborator (a composer, an arranger) doesn't match that, so this sheet
/// never shows it for someone who doesn't have one yet. That's not a gap: a
/// `Person` first gains an address via `PersonAddressPromptSheet`, shown
/// immediately after being selected as Declarant/Director if they're
/// missing one (`PartyPickerView.promptsForMissingAddressOnSelect`) — this
/// sheet's own job is narrower, just correcting a mistake in an address that
/// already exists. **Replaces an earlier, more complicated design** (a
/// `showsAddressField` parameter threaded through `PartyPickerView`/
/// `MultiPartyFieldBucket`/`CollaboratorPersonBucket`, keyed off whether the
/// person currently held an address-requiring *role*) — that design had a
/// real bug: once `showsAddressField` defaulted to `false` for every edit
/// path, there was no way to ever correct an address after it was set.
/// `existing?.address != nil` fixes that directly: correctable whenever one
/// exists, never shown as clutter when one doesn't, with no role-awareness
/// needed anywhere. See `docs/DECISIONS.md`, 2026-10-03.
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
    /// Seeds every field below from the app owner's own stored
    /// `ComposerProfile` instead of `existing` — set only by "That's Me"
    /// (`PartyPickerView`), and only meaningful when `existing == nil`
    /// (editing an existing `Person` always shows that `Person`'s own data,
    /// never the profile's). Pre-fills as ordinary, visible, editable
    /// `@State` text — the same fields the user would otherwise type by
    /// hand — never a locked/read-only auto-insert; the user can freely
    /// change anything before saving, same as any other new entry.
    let prefillingFromProfile: ComposerProfile?
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
    /// Only ever read/written when `showsAddressSection` is `true` — see
    /// that computed property's doc comment. Seeded from `existing?.address`
    /// regardless (harmless when unused), the same pattern every other field
    /// here uses.
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
        prefillingFromProfile: ComposerProfile? = nil,
        onSave: @escaping (Person) async -> SavePersonResult?,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.initialIntendedRole = initialIntendedRole
        self.showsIPINumberField = showsIPINumberField
        self.prefillingFromProfile = prefillingFromProfile
        self.onSave = onSave
        self.onCancel = onCancel
        // `existing` always wins when both are somehow present — only
        // "That's Me" ever sets `prefillingFromProfile`, and it only ever
        // does so for a brand-new entry (`existing == nil`).
        let profile = existing == nil ? prefillingFromProfile : nil
        _firstName = State(initialValue: existing?.firstName ?? profile?.firstName ?? "")
        _lastName = State(initialValue: existing?.lastName ?? profile?.lastName ?? "")
        _ipiNumber = State(initialValue: existing?.ipiNumber ?? profile?.ipiNumber ?? "")
        _email = State(initialValue: existing?.email ?? profile?.email ?? "")
        _swissPerformNumber = State(initialValue: existing?.swissPerformNumber ?? profile?.swissPerformNumber ?? "")
        let address = existing?.address ?? profile?.address
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

    /// Only assembled/consulted when `showsAddressSection` is `true` — see
    /// `save()`. Unlike `LabelEditorSheet.currentAddress` (always required),
    /// an incomplete entry here simply means "no address," not a blocked
    /// save — `Person.address` is optional, so this sheet's `canSave` never
    /// depends on address completeness the way `LabelEditorSheet`'s does.
    private var currentAddress: PostalAddress {
        PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }

    /// Whether to show (and allow correcting) the address section — `true`
    /// iff `existing` already has one. See this type's own doc comment for
    /// why this replaced an external `showsAddressField` parameter: address
    /// capture for someone who *doesn't* have one yet happens via
    /// `PersonAddressPromptSheet`, triggered at selection time, never here.
    private var showsAddressSection: Bool {
        existing?.address != nil || (existing == nil && prefillingFromProfile?.address != nil)
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
            if showsAddressSection {
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
            address: showsAddressSection ? (currentAddress.isComplete ? currentAddress : nil) : existing?.address,
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
