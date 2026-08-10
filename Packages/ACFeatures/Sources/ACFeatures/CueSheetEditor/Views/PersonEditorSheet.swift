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
/// **Deliberately has no address field.** `Person.address` is optional
/// generally (SPEC.md §4.5) — required only when a `Person` is used as
/// `Setup.producer`/`.directorOrPrincipal`/`.declarant`, unlike `Label`,
/// whose address is always required. Prompting for it on every ordinary
/// collaborator (a composer, an arranger) doesn't match that — this sheet
/// leaves `address` untouched, never showing UI for it. On an *edit* of an
/// existing `Person` that already has an address (e.g. one previously used
/// as a producer), `save()` preserves `existing?.address` unchanged rather
/// than silently clearing it — this sheet just never offers to *set* one.
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
    @State private var duplicateNameWarning: String?
    @State private var isSaving = false

    init(
        existing: Person?,
        initialIntendedRole: PersonIntendedRole? = nil,
        onSave: @escaping (Person) async -> SavePersonResult?,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.initialIntendedRole = initialIntendedRole
        self.onSave = onSave
        self.onCancel = onCancel
        _firstName = State(initialValue: existing?.firstName ?? "")
        _lastName = State(initialValue: existing?.lastName ?? "")
        _ipiNumber = State(initialValue: existing?.ipiNumber ?? "")
        _email = State(initialValue: existing?.email ?? "")
        _swissPerformNumber = State(initialValue: existing?.swissPerformNumber ?? "")
    }

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            GhostTextField(placeholder: "IPI Number (optional)", text: $ipiNumber)
            GhostTextField(placeholder: "Email (optional)", text: $email)

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
            address: existing?.address,
            email: email.isEmpty ? nil : email,
            swissPerformNumber: swissPerformNumber.isEmpty ? nil : swissPerformNumber,
            intendedRoles: intendedRoles
        )
        print("DIAG PersonEditorSheet.save() ENTER \(person.firstName) \(person.lastName)")
        isSaving = true
        Task {
            let result = await onSave(person)
            print("DIAG PersonEditorSheet.save() Task got result \(String(describing: result))")
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
