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
struct PersonEditorSheet: View {
    let existing: Person?
    let onSave: (Person) -> Void
    let onCancel: () -> Void

    @State private var firstName: String
    @State private var lastName: String
    @State private var ipiNumber: String
    @State private var email: String
    @State private var swissPerformNumber: String
    @State private var hasAddress: Bool
    @State private var street: String
    @State private var postalCode: String
    @State private var city: String
    @State private var country: String

    init(existing: Person?, onSave: @escaping (Person) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _firstName = State(initialValue: existing?.firstName ?? "")
        _lastName = State(initialValue: existing?.lastName ?? "")
        _ipiNumber = State(initialValue: existing?.ipiNumber ?? "")
        _email = State(initialValue: existing?.email ?? "")
        _swissPerformNumber = State(initialValue: existing?.swissPerformNumber ?? "")
        let address = existing?.address
        _hasAddress = State(initialValue: address != nil)
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

    private var currentAddress: PostalAddress {
        PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }

    private var canSave: Bool {
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty && (!hasAddress || currentAddress.isComplete)
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

            Toggle("Address", isOn: $hasAddress)
                .toggleStyle(.checkbox)
                .foregroundStyle(Theme.Surface.primary.foreground)
            if hasAddress {
                PostalAddressFields(street: $street, postalCode: $postalCode, city: $city, country: $country)
            }

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
    }

    private func save() {
        let person = Person(
            id: existing?.id ?? UUID(),
            firstName: trimmedFirstName,
            lastName: trimmedLastName,
            ipiNumber: ipiNumber.isEmpty ? nil : ipiNumber,
            address: hasAddress ? currentAddress : nil,
            email: email.isEmpty ? nil : email,
            swissPerformNumber: swissPerformNumber.isEmpty ? nil : swissPerformNumber
        )
        onSave(person)
    }
}
