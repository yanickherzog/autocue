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
    /// Pre-fills `Person.intendedRole` when creating a new `Person` from one
    /// of the Setup screen's collaborator-roster buckets (`ROADMAP.md` D7) —
    /// ignored when `existing != nil`, since editing preserves whatever role
    /// hint the person already has. No UI control for this field in this
    /// sheet: it's set entirely by which roster bucket's "+ Add" button was
    /// used, not something this form exposes for reassignment.
    let initialIntendedRole: PersonIntendedRole?
    let onSave: (Person) -> Void
    let onCancel: () -> Void

    @State private var firstName: String
    @State private var lastName: String
    @State private var ipiNumber: String
    @State private var email: String
    @State private var swissPerformNumber: String

    init(
        existing: Person?,
        initialIntendedRole: PersonIntendedRole? = nil,
        onSave: @escaping (Person) -> Void,
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
            Text(existing == nil ? "New Person" : "Edit Person")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            HStack(spacing: Theme.Spacing.sm) {
                GhostTextField(placeholder: "First Name", text: $firstName)
                GhostTextField(placeholder: "Last Name", text: $lastName)
            }
            GhostTextField(placeholder: "IPI Number (optional)", text: $ipiNumber)
            GhostTextField(placeholder: "Email (optional)", text: $email)
            GhostTextField(placeholder: "SWISSPERFORM Number (optional)", text: $swissPerformNumber)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                Button("Save", action: save)
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
    }

    private func save() {
        let person = Person(
            id: existing?.id ?? UUID(),
            firstName: trimmedFirstName,
            lastName: trimmedLastName,
            ipiNumber: ipiNumber.isEmpty ? nil : ipiNumber,
            address: existing?.address,
            email: email.isEmpty ? nil : email,
            swissPerformNumber: swissPerformNumber.isEmpty ? nil : swissPerformNumber,
            intendedRole: existing?.intendedRole ?? initialIntendedRole
        )
        onSave(person)
    }
}
