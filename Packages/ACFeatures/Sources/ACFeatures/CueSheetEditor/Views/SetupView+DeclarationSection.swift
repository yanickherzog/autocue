import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Declaration" section — additional-undeclared-works
/// tri-state, ISAN/SUISA registration numbers, declarant, declaration date.
/// See `SetupView`'s own doc comment for why this screen is split across
/// files.
///
/// **Deliberately does not show `AttachmentTypePicker`.** `attachmentTypes`
/// is optional per SPEC.md §4.2 ("informational flags only") and unused in
/// practice — hidden from the UI rather than removed from the domain model,
/// per `docs/DECISIONS.md`. Flagged alongside the other items already
/// queued for `ROADMAP.md` D11/T11.3's SUISA revalidation checkpoint, in
/// case the real form does need it after all.
extension SetupView {
    var declarationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Declaration")
            additionalWorksPicker
            GhostTextField(
                placeholder: "ISAN Number",
                text: field({ $0.isanNumber ?? "" }, { $0.updating(isanNumber: .some($1.isEmpty ? nil : $1)) })
            )
            if let suisaRegistrationNumber = draft.suisaRegistrationNumber {
                // Not user-entered (SPEC.md §4.2) — assigned by SUISA after
                // submission, so this is display-only, never an input field.
                HStack {
                    Text("SUISA Registration Number")
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                    Spacer()
                    Text(suisaRegistrationNumber)
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                }
            }
            partyFieldRow(title: "Declarant", party: draft.declarant, field: .declarant)
            DatePicker(
                "Declaration Date",
                selection: field({ $0.declarationDate }, { $0.updating(declarationDate: $1) }),
                displayedComponents: .date
            )
            // .field, not the .automatic default — .automatic renders a
            // numeric-stepper affordance next to the date box on macOS,
            // which reads as "increment/decrement a number," not "pick a
            // date." Confirmed via a real rendered window, not assumed.
            .datePickerStyle(.field)
            .foregroundStyle(Theme.Surface.primary.foreground)
        }
    }

    var additionalWorksPicker: some View {
        Picker(
            "Contains Additional Undeclared Works",
            selection: immediateField(
                { $0.containsAdditionalUndeclaredWorks },
                { $0.updating(containsAdditionalUndeclaredWorks: $1) }
            )
        ) {
            Text("Yes").tag(AdditionalWorksDeclaration.yes)
            Text("No").tag(AdditionalWorksDeclaration.no)
            Text("Not Known").tag(AdditionalWorksDeclaration.notKnown)
        }
        .foregroundStyle(Theme.Surface.primary.foreground)
    }
}
