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
    /// Overrides the displayed "New {displayName}"/"Edit {displayName}"
    /// title text — never the underlying `ACCore.Label` type or any other
    /// field on this sheet. Defaults to `"Label"` (unchanged everywhere this
    /// sheet is reached from the standalone Label roster bucket); Producer*in
    /// passes `"Company"` instead, since that picker refers to the same
    /// entity type as "Company" throughout — see `PartyPickerView`'s
    /// `labelDisplayName` doc comment and `docs/DECISIONS.md`.
    let displayName: String
    /// Hides the "Kind" field entirely when `false` — used only by the
    /// standalone Label roster bucket (`CollaboratorLabelBucket`), where
    /// every entry is definitionally a `Label`, so there's nothing to ask.
    /// The underlying `kind` value is neither shown nor touched in that
    /// case — it stays whatever it already was (`nil` for a brand-new
    /// entry, matching `LabelKind`'s existing default; unchanged on save
    /// for an existing entry). Defaults to `true` (unchanged everywhere
    /// else this sheet is reached from).
    var showsKindField = true
    /// When non-`nil`, a **newly-created** entry's `kind` defaults to this
    /// value and the "Unspecified" option is omitted from the picker
    /// entirely — used only by the "+ New Company" sheet Producer*in's
    /// picker presents (`.productionCompany`), where a blank/unspecified
    /// Kind never makes sense for a value being created there. Has no
    /// effect when editing an existing entry (`existing != nil`): "Unspecified"
    /// always stays available then, since an existing entry — created via
    /// some other flow, e.g. the standalone Label bucket, which never asks
    /// for Kind at all — may genuinely already have a `nil` kind, and the
    /// picker must be able to represent that instead of showing a broken
    /// selection. `nil` (every other call site) preserves the original
    /// "Unspecified"-default, "Unspecified"-always-offered behavior.
    var newEntryDefaultKind: LabelKind?
    /// Pre-fills a newly-created `Label`'s `intendedForLabelRoster` — `true`
    /// only for the standalone Label roster bucket's own "+ New Company"
    /// sub-sheet (`CollaboratorLabelBucket`); `false` (default) everywhere
    /// else, including Producer*in's "+ New Company." Ignored when
    /// `existing != nil` — editing preserves whatever the entry's flag
    /// already is, the same "not something this form exposes for
    /// reassignment directly" reasoning `PersonEditorSheet.initialIntendedRole`
    /// already establishes for `Person`. See `ACCore.Label.intendedForLabelRoster`'s
    /// own doc comment and `docs/DECISIONS.md`.
    var initialIntendedForLabelRoster = false
    /// `async`, returning `SaveLabelResult` — see `PersonEditorSheet.onSave`'s
    /// doc comment for the full reasoning; same shape here.
    let onSave: (ACCore.Label) async -> SaveLabelResult?
    let onCancel: () -> Void

    @State private var name: String
    /// **No UI field for this — deliberately.** Companies never carry an IPI
    /// number under any circumstances (unlike `Person`, where IPI-Nr is only
    /// conditionally hidden for the Producer*in/Regisseur*in creation flow
    /// specifically) — confirmed directly, not assumed; SPEC.md §4.5's
    /// original note describing this as a "publisher CAE/IPI number" was
    /// itself the mistake, corrected in the same change this doc comment
    /// belongs to. Still round-tripped unchanged on edit (seeded from
    /// `existing`, written back as-is in `save()`), the same "hidden from
    /// the form, never silently cleared" pattern already established for
    /// `Person.swissPerformNumber`/`.address` (before this bucket's own
    /// address addition) — an existing `Label` that already has a value here
    /// from before this fix isn't silently wiped by opening this sheet.
    @State private var ipiNumber: String
    @State private var kind: LabelKind?
    @State private var street: String
    @State private var postalCode: String
    @State private var city: String
    @State private var country: String
    @State private var duplicateNameWarning: String?
    @State private var isSaving = false

    init(
        existing: ACCore.Label?,
        displayName: String = "Label",
        showsKindField: Bool = true,
        newEntryDefaultKind: LabelKind? = nil,
        initialIntendedForLabelRoster: Bool = false,
        onSave: @escaping (ACCore.Label) async -> SaveLabelResult?,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.displayName = displayName
        self.showsKindField = showsKindField
        self.newEntryDefaultKind = newEntryDefaultKind
        self.initialIntendedForLabelRoster = initialIntendedForLabelRoster
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        _ipiNumber = State(initialValue: existing?.ipiNumber ?? "")
        _kind = State(initialValue: existing?.kind ?? newEntryDefaultKind)
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
            Text(existing == nil ? "New \(displayName)" : "Edit \(displayName)")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            GhostTextField(placeholder: "Company Name", text: $name)
            if showsKindField {
                kindPicker
            }
            PostalAddressFields(street: $street, postalCode: $postalCode, city: $city, country: $country)

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

    /// "Unspecified" is omitted only when creating a brand-new entry with a
    /// `newEntryDefaultKind` set (the "+ New Company" flow) — see that
    /// property's doc comment for why it always stays offered when editing.
    private var showsUnspecifiedKindOption: Bool {
        existing != nil || newEntryDefaultKind == nil
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            if showsUnspecifiedKindOption {
                Text("Unspecified").tag(LabelKind?.none)
            }
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
            kind: kind,
            intendedForLabelRoster: existing?.intendedForLabelRoster ?? initialIntendedForLabelRoster
        )
        isSaving = true
        Task {
            let result = await onSave(label)
            isSaving = false
            if case let .duplicateName(existingMatch) = result {
                duplicateNameWarning =
                    "\(existingMatch.name) is already in this project's directory. " +
                    "Use a different name, or select the existing entry instead of adding a duplicate."
            }
        }
    }
}
