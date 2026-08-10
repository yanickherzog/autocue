import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Declaration" section — additional-undeclared-works
/// tri-state, ISAN/SUISA registration numbers, declarant, declaration date,
/// attachments. See `SetupView`'s own doc comment for why this screen is
/// split across files.
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
            .foregroundStyle(Theme.Surface.primary.foreground)
            AttachmentTypePicker(
                selection: immediateField({ $0.attachmentTypes }, { $0.updating(attachmentTypes: $1) }),
                otherDescription: field(
                    { $0.otherAttachmentDescription ?? "" },
                    { $0.updating(otherAttachmentDescription: .some($1.isEmpty ? nil : $1)) }
                )
            )
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
