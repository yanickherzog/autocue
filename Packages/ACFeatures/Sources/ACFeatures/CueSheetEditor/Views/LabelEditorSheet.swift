import ACCore
import ACDesignSystem
import SwiftUI

/// Create/edit sheet for one corporate right-holder (`ACCore.Label`,
/// SPEC.md §4.5) — same shape as `PersonEditorSheet`. Unlike `Person.address`
/// (optional), a Label's address is always required — "complete address" is
/// mandatory wherever a company stands in on the form — so there's no
/// "has address" toggle here.
///
/// Qualifies every reference to the domain type as `ACCore.Label`
/// throughout this file — `SwiftUI.Label` (the icon+title view type) is also
/// in scope via `import SwiftUI`, and the two names collide.
struct LabelEditorSheet: View {
    let existing: ACCore.Label?
    let onSave: (ACCore.Label) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var ipiNumber: String
    @State private var kind: LabelKind?
    @State private var street: String
    @State private var postalCode: String
    @State private var city: String
    @State private var country: String

    init(existing: ACCore.Label?, onSave: @escaping (ACCore.Label) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        _ipiNumber = State(initialValue: existing?.ipiNumber ?? "")
        _kind = State(initialValue: existing?.kind)
        let address = existing?.address
        _street = State(initialValue: address?.street ?? "")
        _postalCode = State(initialValue: address?.postalCode ?? "")
        _city = State(initialValue: address?.city ?? "")
        _country = State(initialValue: address?.country ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentAddress: PostalAddress {
        PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && currentAddress.isComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(existing == nil ? "New Label" : "Edit Label")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            GhostTextField(placeholder: "Company Name", text: $name)
            GhostTextField(placeholder: "IPI Number (optional)", text: $ipiNumber)
            kindPicker
            PostalAddressFields(street: $street, postalCode: $postalCode, city: $city, country: $country)

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

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            Text("Unspecified").tag(LabelKind?.none)
            Text("Publisher").tag(LabelKind?.some(.publisher))
            Text("Production Company").tag(LabelKind?.some(.productionCompany))
            Text("Broadcaster").tag(LabelKind?.some(.broadcaster))
            Text("Other").tag(LabelKind?.some(.other))
        }
        .foregroundStyle(Theme.Surface.primary.foreground)
    }

    private func save() {
        let label = ACCore.Label(
            id: existing?.id ?? UUID(),
            name: trimmedName,
            address: currentAddress,
            ipiNumber: ipiNumber.isEmpty ? nil : ipiNumber,
            kind: kind
        )
        onSave(label)
    }
}
